-------------------------------------------------------------------------------
-- Facts: what the game says about one item in the bags, for the rules
--
-- Read(bag, slot, info) returns a facts table, or nil when the slot is gone:
--   loaded       item info was ready (false: the rules keep it and wait)
--   itemID, link, name, icon, quality, count, sellPrice, classID,
--   subclassID, bindType, equipLoc, itemLevel
--   bound        C_Item.IsBound (false means it can be traded or posted)
--   warbound     warbound until equipped (this copy, IsBoundToAccountUntilEquip)
--   accountBound bound to the warband or account in any way: bind type 7, 8
--                or 9, C_Item.IsItemBindToAccount, or warbound; another of
--                the player's characters could use it, and the AH can't
--   quest        a quest item or quest starter
--   inSet        in an equipment set
--   openable, hasNoValue, locked (from the slot)
--   appearance   "collected", "missing", "unknown" (not readable yet) or
--                "none" (no look to collect: jewelry, trinkets, non-gear)
--   collectible  nil, or { kind = "mount" | "pet" | "toy", collected }
--   level        gear only (a slot with a look, neck, finger, trinket): its
--                real item level in this bag slot (GetCurrentItemLevel), nil
--                for anything else
--   upgrade      item level above the player's equipped average
--   hasUse       it has a Use spell
--   usable       it has a Use spell and this character can use it now
--   forMyClass   for an epic Miscellaneous item with a Use (a token) only: true when
--                its "Classes:" line names this character's class, false
--                when it names others only, nil without such a line
--   classToken   a Use, and meant for this character's class: its Classes
--                line says so, or (no line) it is usable and
--                C_Item.IsItemSpecificToPlayerClass agrees
--   otherClass   a Use meant for other classes: the Classes line leaves
--                this class out, or (no line) the game says it can't be used
-- Every client call goes through Facts._test.seams and fails soft: a call
-- that errors leaves its fact unknown, which the rules treat as Keep.
-------------------------------------------------------------------------------
local Facts = {}
CobysLootSweeper.Facts = Facts

local Utilities = CobysLootSweeper.Utilities
local Try, IsSecret = Utilities.Try, Utilities.IsSecret

-- Equip slots that carry a look the wardrobe can collect
local APPEARANCE_SLOTS = {
  INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true, INVTYPE_CHEST = true,
  INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
  INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_CLOAK = true, INVTYPE_WEAPON = true,
  INVTYPE_SHIELD = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true, INVTYPE_TABARD = true,
}
Facts.APPEARANCE_SLOTS = APPEARANCE_SLOTS

local seams = {
  ItemInfo = function(link) return C_Item.GetItemInfo(link) end,
  IsBound = function(loc) return C_Item.IsBound(loc) end,
  IsWarbound = function(loc) return C_Item.IsBoundToAccountUntilEquip(loc) end,
  QuestInfo = function(bag, slot) return C_Container.GetContainerItemQuestInfo(bag, slot) end,
  InSet = function(bag, slot) return C_Container.GetContainerItemEquipmentSetInfo(bag, slot) end,
  ItemLevel = function(loc) return C_Item.GetCurrentItemLevel(loc) end,
  EquippedAverage = function() return select(2, GetAverageItemLevel()) end,
  TransmogItem = function(link) return C_TransmogCollection.GetItemInfo(link) end,
  SourceInfo = function(sourceID) return C_TransmogCollection.GetAppearanceInfoBySource(sourceID) end,
  MountFromItem = function(itemID) return C_MountJournal.GetMountFromItem(itemID) end,
  MountCollected = function(mountID) return select(11, C_MountJournal.GetMountInfoByID(mountID)) end,
  PetSpecies = function(itemID) return select(13, C_PetJournal.GetPetInfoByItemID(itemID)) end,
  PetOwned = function(speciesID) return C_PetJournal.GetNumCollectedInfo(speciesID) end,
  ToyInfo = function(itemID) return C_ToyBox.GetToyInfo(itemID) end,
  HasToy = function(itemID) return PlayerHasToy(itemID) end,
  ItemSpell = function(link) return C_Item.GetItemSpell(link) end,
  IsUsable = function(link) return C_Item.IsUsableItem(link) end,
  ForMyClass = function(link) return C_Item.IsItemSpecificToPlayerClass(link) end,
  BindToAccount = function(link) return C_Item.IsItemBindToAccount(link) end,
  TooltipLines = function(bag, slot)
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    return data and data.lines
  end,
  PlayerClass = function() return (UnitClass("player")) end,
  ClassesFormat = function() return ITEM_CLASSES_ALLOWED end,
}
Facts._test = { seams = seams }

local ClassFacts   -- forward (defined below Read)

local function Bool(ok, value)
  if not ok or IsSecret(value) or type(value) ~= "boolean" then return nil end
  return value
end

-- The look: "collected" only for a permanently collected source, or a look
-- collected with no conditional hold on this source
function Facts.Appearance(link, equipLoc)
  if not APPEARANCE_SLOTS[equipLoc or ""] then return "none" end
  local ok, _, sourceID = Try(seams.TransmogItem, link)
  if not ok or type(sourceID) ~= "number" or IsSecret(sourceID) then return "unknown" end
  local okS, info = Try(seams.SourceInfo, sourceID)
  if not okS or type(info) ~= "table" or Utilities.IsSecretTable(info) then return "unknown" end
  if info.sourceIsCollectedPermanent == true then return "collected" end
  if info.appearanceIsCollected == true and info.sourceIsCollectedConditional ~= true then
    return "collected"
  end
  return "missing"
end

local function Mount(itemID)
  local ok, mountID = Try(seams.MountFromItem, itemID)
  if not ok or type(mountID) ~= "number" then return nil end
  local okC, collected = Try(seams.MountCollected, mountID)
  return { kind = "mount", collected = Bool(okC, collected) }
end

local function Pet(itemID)
  local ok, speciesID = Try(seams.PetSpecies, itemID)
  if not ok or type(speciesID) ~= "number" or speciesID <= 0 then return nil end
  local okN, owned = Try(seams.PetOwned, speciesID)
  if not okN or type(owned) ~= "number" then return { kind = "pet", collected = nil } end
  return { kind = "pet", collected = owned > 0 }
end

local function Toy(itemID)
  local ok, toyItemID = Try(seams.ToyInfo, itemID)
  if not ok or toyItemID ~= itemID then return nil end
  local okH, has = Try(seams.HasToy, itemID)
  return { kind = "toy", collected = Bool(okH, has) }
end

function Facts.Collectible(itemID, classID)
  if classID ~= 15 and classID ~= 17 then
    return Toy(itemID)
  end
  return Mount(itemID) or Pet(itemID) or Toy(itemID)
end

local function Quest(bag, slot)
  local ok, q = Try(seams.QuestInfo, bag, slot)
  if not ok or type(q) ~= "table" or Utilities.IsSecretTable(q) then return nil end
  return q.isQuestItem == true or type(q.questID) == "number"
end

-- Gear: an equip slot that has a look, or neck, finger, trinket
function Facts.IsGearSlot(equipLoc)
  return APPEARANCE_SLOTS[equipLoc or ""] == true or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER"
    or equipLoc == "INVTYPE_TRINKET"
end

-- The real item level of gear in a bag slot, or nil
local function GearLevel(loc, equipLoc)
  if not Facts.IsGearSlot(equipLoc) then return nil end
  local ok, level = Try(seams.ItemLevel, loc)
  if not ok or type(level) ~= "number" or IsSecret(level) or level <= 0 then return nil end
  return level
end

local function Upgrade(level)
  if not level then return false end
  local okA, average = Try(seams.EquippedAverage)
  if not okA or type(average) ~= "number" then return false end
  return level > average
end

local function ItemInfoFacts(facts, link)
  local ok, name, _, quality, itemLevel, _, _, _, _, equipLoc, icon, sellPrice, classID, subclassID, bindType =
    Try(seams.ItemInfo, link)
  if not ok or name == nil or IsSecret(name) then return false end
  facts.name, facts.quality, facts.itemLevel, facts.equipLoc, facts.icon = name, quality, itemLevel, equipLoc, icon
  facts.sellPrice = type(sellPrice) == "number" and sellPrice or 0
  facts.classID, facts.subclassID, facts.bindType = classID, subclassID, bindType
  return true
end

-- info: the slot's C_Container.GetContainerItemInfo table
function Facts.Read(bag, slot, info)
  if type(info) ~= "table" then return nil end
  local link, itemID = info.hyperlink, info.itemID
  local facts = {
    itemID = itemID, link = link, count = info.stackCount, icon = info.iconFileID,
    quality = info.quality, openable = info.hasLoot == true, hasNoValue = info.hasNoValue == true,
    locked = info.isLocked == true, name = info.itemName,
  }
  facts.loaded = ItemInfoFacts(facts, link)
  local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
  local okB, bound = Try(seams.IsBound, loc)
  facts.bound = Bool(okB, bound)
  if facts.bound == nil then facts.bound = info.isBound == true end
  local okW, warbound = Try(seams.IsWarbound, loc)
  facts.warbound = Bool(okW, warbound) == true
  facts.quest = Quest(bag, slot)
  local okS, inSet = Try(seams.InSet, bag, slot)
  facts.inSet = Bool(okS, inSet) == true
  if facts.loaded then
    facts.appearance = Facts.Appearance(link, facts.equipLoc)
    facts.collectible = Facts.Collectible(itemID, facts.classID)
    facts.level = GearLevel(loc, facts.equipLoc)
    facts.upgrade = Upgrade(facts.level)
    facts.usable, facts.hasUse = Facts.Usable(link)
    facts.accountBound = facts.warbound or Facts.AccountBound(link, facts.bindType)
    ClassFacts(facts, bag, slot, link)
  end
  return facts
end

-- usable, hasUse: a Use spell, and whether this character can use it (the
-- game's own answer; nil when it can't be read, never taken as "no":
-- FACT-01)
function Facts.Usable(link)
  local okS, spellName = Try(seams.ItemSpell, link)
  if not okS or spellName == nil or IsSecret(spellName) then return false, false end
  local okU, usable = Try(seams.IsUsable, link)
  return Bool(okU, usable), true
end

-- The classes an item's tooltip allows ("Classes: Hunter, Mage, Druid"),
-- matched against the game's own format string, so any language works:
-- true when this character's class is named, false when only others are,
-- nil when there is no such line or it can't be read
function Facts.ClassesAllow(bag, slot)
  local okF, format = Try(seams.ClassesFormat)
  local okP, mine = Try(seams.PlayerClass)
  if not okF or type(format) ~= "string" or not okP or type(mine) ~= "string" or IsSecret(mine) then return nil end
  local prefix = format:match("^(.-)%%s")
  if not prefix or prefix == "" then return nil end
  local ok, lines = Try(seams.TooltipLines, bag, slot)
  if not ok or type(lines) ~= "table" or Utilities.IsSecretTable(lines) then return nil end
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and line.leftText
    if type(text) == "string" and not IsSecret(text) then
      text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if text:sub(1, #prefix) == prefix then
        for name in text:sub(#prefix + 1):gmatch("[^,]+") do
          if strtrim(name) == mine then return true end
        end
        return false
      end
    end
  end
  return nil
end

-- forMyClass, classToken and otherClass: only epic Miscellaneous items
-- with a Use (tokens) are looked at, so ordinary rows cost no tooltip read
ClassFacts = function(facts, bag, slot, link)
  if facts.classID ~= 15 or (facts.quality or 0) < 4 or not facts.hasUse then return end
  facts.forMyClass = Facts.ClassesAllow(bag, slot)
  if facts.forMyClass ~= nil then
    facts.classToken = facts.forMyClass
    facts.otherClass = not facts.forMyClass
    return
  end
  if facts.usable then
    local okC, mine = Try(seams.ForMyClass, link)
    facts.classToken = Bool(okC, mine) == true
  end
  facts.otherClass = facts.usable == false
end

-- Bound to the warband or account (bind types ToWoWAccount 7, ToBnetAccount
-- 8, ToBnetAccountUntilEquipped 9)
local ACCOUNT_BINDS = { [7] = true, [8] = true, [9] = true }
function Facts.AccountBound(link, bindType)
  if ACCOUNT_BINDS[bindType or -1] then return true end
  local ok, bound = Try(seams.BindToAccount, link)
  return Bool(ok, bound) == true
end
