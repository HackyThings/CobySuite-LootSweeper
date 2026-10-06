-------------------------------------------------------------------------------
-- Facts: what the game says about one item in the bags, for the rules
--
-- Read(bag, slot, info) returns a facts table, or nil when the slot is gone:
--   loaded       item info was ready (false: the rules keep it and wait)
--   itemID, link, name, icon, quality, count, sellPrice, classID,
--   bindType, equipLoc
--   bound        C_Item.IsBound (false means it can be traded or posted)
--   warbound     warbound until equipped (this copy, IsBoundToAccountUntilEquip)
--   accountBound bound to the warband or account in any way: bind type 7, 8
--                or 9, C_Item.IsItemBindToAccount, or warbound; another of
--                the player's characters could use it, and the AH can't
--   quest        a quest item or quest starter
--   inSet        in an equipment set
--   openable, hasNoValue (from the slot)
--   appearance   "collected", "missing", "unknown" (not readable yet) or
--                "none" (no look to collect: jewelry, trinkets, non-gear)
--   collectible  nil, or { kind = "mount" | "pet" | "toy", collected }
--   level        gear only (a slot with a look, neck, finger, trinket): its
--                real item level in this bag slot (GetCurrentItemLevel), nil
--                for anything else
--   gear         weapons and armor worn for their stats (not shirts or
--                tabards): the gear rules apply (AllContent-Plan.md section 3)
--   reach        gear: the item level it can reach (its upgrade track's
--                highest, else its own); nil when its level can't be read
--   track        gear: "track" (an upgrade track was read, with its highest
--                level, or fully upgraded), "partial" (upgrades left but no
--                highest level given: Check Sweep, 2026-10-01, saw
--                maxItemLevel 0 on a Hero 6/6 piece away from the upgrade
--                NPC), "none" (the game says it has none) or "unknown"
--   bar          gear: the item level worn where it would go (the lower of
--                two rings, trinkets or weapons it could replace); nil with
--                barWhy "empty" (nothing worn there) or "unknown" (unreadable)
--   forClass     gear: false only when the item names the specs it is for and
--                none is this class's (nil: no list, or unreadable)
--   forSpec      gear: false when it names this class's specs but not the
--                current one
--   convertible  gear: the game says this character can convert it
--   expansionID, setID   from the item's info; currentExpansion when its
--                expansion is the server's
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
  WornLink = function(slot) return GetInventoryItemLink("player", slot) end,
  WornLevel = function(slot) return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot)) end,
  WornEquipLoc = function(link) return select(4, C_Item.GetItemInfoInstant(link)) end,
  UpgradeInfo = function(link) return C_Item.GetItemUpgradeInfo(link) end,
  Convertible = function(loc) return C_Item.IsItemConvertibleAndValidForPlayer(loc) end,
  ClassID = function() return select(3, UnitClass("player")) end,
  SpecID = function()
    local index = C_SpecializationInfo.GetSpecialization()
    return index and C_SpecializationInfo.GetSpecializationInfo(index)
  end,
  ItemSpecs = function(link) return C_Item.GetItemSpecInfo(link) end,
  ClassSpecs = function(classID)
    local ids = {}
    for i = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0 do
      ids[#ids + 1] = (GetSpecializationInfoForClassID(classID, i))
    end
    return ids
  end,
  ServerExpansion = function() return GetServerExpansionLevel() end,
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

local function ItemInfoFacts(facts, link)
  local ok, name, _, quality, _, _, _, _, _, equipLoc, icon, sellPrice, classID, _, bindType,
    expansionID, setID, isCraftingReagent = Try(seams.ItemInfo, link)
  if not ok or name == nil or IsSecret(name) then return false end
  facts.name, facts.quality, facts.equipLoc, facts.icon = name, quality, equipLoc, icon
  facts.sellPrice = type(sellPrice) == "number" and sellPrice or 0
  facts.classID, facts.bindType = classID, bindType
  facts.expansionID = type(expansionID) == "number" and not IsSecret(expansionID) and expansionID or nil
  facts.setID = type(setID) == "number" and not IsSecret(setID) and setID > 0 and setID or nil
  facts.reagent = isCraftingReagent == true   -- a crafting reagent (counted in a bulk sale's review)
  return true
end

-------------------------------------------------------------------------------
-- Gear: what it can reach, and what is worn where it would go
-------------------------------------------------------------------------------
-- Where each kind of gear is worn (equipment slot IDs); two slots for
-- rings, trinkets and one-handed weapons
local WORN = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_2HWEAPON = { 16, 17 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}
local MAIN_HAND, OFF_HAND = 16, 17
local OFF_HAND_WEAPONS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_2HWEAPON = true }

local worn = nil   -- [slot] = { level, equipLoc } or false (empty), for one build of the view

-- BeginRead(): the next reads look at what is worn now (Pile calls it once
-- per build of the view)
function Facts.BeginRead() worn = {} end

-- What is worn in a slot: { level, equipLoc } or nil, then whether the slot
-- is empty (true) or can't be read (false)
local function Worn(slot)
  worn = worn or {}
  if worn[slot] ~= nil then return worn[slot] or nil, worn[slot] == false end
  local okL, link = Try(seams.WornLink, slot)
  if not okL or IsSecret(link) then return nil, false end
  if link == nil then
    worn[slot] = false
    return nil, true
  end
  local okV, level = Try(seams.WornLevel, slot)
  if not okV or type(level) ~= "number" or IsSecret(level) or level <= 0 then return nil, false end
  local okE, equipLoc = Try(seams.WornEquipLoc, link)
  worn[slot] = { level = level, equipLoc = okE and type(equipLoc) == "string" and equipLoc or nil }
  return worn[slot], false
end

-- Bar(equipLoc): the item level worn where this gear would go, or nil and
-- why ("empty" or "unknown")
function Facts.Bar(equipLoc)
  local slots = WORN[equipLoc or ""]
  if not slots then return nil, "unknown" end
  local main, mainEmpty = Worn(MAIN_HAND)
  local function Level(slot)
    local w, empty = Worn(slot)
    if w then return w.level end
    -- An off hand under a two-handed weapon compares with that weapon
    if empty and slot == OFF_HAND and main and main.equipLoc == "INVTYPE_2HWEAPON" then return main.level end
    return nil, empty and "empty" or "unknown"
  end
  if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" then
    -- Weapons compare with the weapons worn: an off hand that is a shield or
    -- held item isn't one it could replace
    if not main then return nil, mainEmpty and "empty" or "unknown" end
    local off, offEmpty = Worn(OFF_HAND)
    -- An off hand that is there but can't be read, or whose kind can't be,
    -- might be a weaker weapon: unknown, never the main hand alone (review
    -- 2026-10-01, GEAR-01)
    if not off and not offEmpty then return nil, "unknown" end
    if off and off.equipLoc == nil then return nil, "unknown" end
    if off and OFF_HAND_WEAPONS[off.equipLoc] then return math.min(main.level, off.level) end
    return main.level
  end
  local lowest
  for _, slot in ipairs(slots) do
    local level, why = Level(slot)
    if not level then return nil, why end
    lowest = lowest and math.min(lowest, level) or level
  end
  return lowest
end

-- LowestWorn() -> level, equipLoc, or nil and why ("empty": nothing worn
-- that can be read; "unknown": unreadable): the worn slot with the lowest
-- item level, for the settings window's gear example
local EXAMPLE_SLOTS = {
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WAIST", "INVTYPE_LEGS",
  "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_CLOAK",
  "INVTYPE_WEAPONMAINHAND",
}
function Facts.LowestWorn()
  Facts.BeginRead()
  local lowest, where, why = nil, nil, "empty"
  for _, equipLoc in ipairs(EXAMPLE_SLOTS) do
    local level, slotWhy = Facts.Bar(equipLoc)
    if level then
      if not lowest or level < lowest then lowest, where = level, equipLoc end
    elseif slotWhy == "unknown" then
      why = "unknown"
    end
  end
  if lowest then return lowest, where end
  return nil, nil, why
end

-- Gear worn for its stats: weapons and armor, not shirts or tabards
function Facts.IsStatGear(facts)
  return (facts.classID == 2 or facts.classID == 4) and WORN[facts.equipLoc or ""] ~= nil
end

-- Track(facts, ok, info): what the upgrade answer says; raises facts.reach
-- to the track's highest level when the game gives one
function Facts.Track(facts, ok, info)
  if not ok then return "unknown" end
  if info == nil then return "none" end
  if type(info) ~= "table" or Utilities.IsSecretTable(info) then return "unknown" end
  local max, current, last = info.maxItemLevel, info.currentLevel, info.maxLevel
  if type(max) == "number" and max > 0 then
    if facts.reach then facts.reach = math.max(facts.reach, max) end
    return "track"
  end
  if type(current) == "number" and type(last) == "number" and current >= last then return "track" end
  return "partial"
end

local function GearFacts(facts, loc, link)
  facts.gear = true
  facts.reach = facts.level
  facts.track = Facts.Track(facts, Try(seams.UpgradeInfo, link))
  facts.bar, facts.barWhy = Facts.Bar(facts.equipLoc)
  facts.forClass, facts.forSpec = Facts.SpecFit(link)
  local okV, convertible = Try(seams.Convertible, loc)
  facts.convertible = Bool(okV, convertible) == true
  -- An unreadable server expansion counts as this expansion: the careful side
  local okX, server = Try(seams.ServerExpansion)
  if not okX or type(server) ~= "number" or IsSecret(server) then
    facts.currentExpansion = true
  else
    facts.currentExpansion = facts.expansionID ~= nil and facts.expansionID >= server
  end
end

-- SpecFit(link) -> forClass, forSpec: from the specs the item names. Only a
-- list that names specs, none of them this class's, makes forClass false;
-- no list (most old gear), or one that can't be read, leaves both nil
function Facts.SpecFit(link)
  local ok, specs = Try(seams.ItemSpecs, link)
  if not ok or type(specs) ~= "table" or Utilities.IsSecretTable(specs) or #specs == 0 then return nil, nil end
  local okC, classID = Try(seams.ClassID)
  if not okC or type(classID) ~= "number" then return nil, nil end
  local okL, mine = Try(seams.ClassSpecs, classID)
  if not okL or type(mine) ~= "table" or #mine == 0 then return nil, nil end
  local ofClass = {}
  for _, id in ipairs(mine) do ofClass[id] = true end
  local okS, current = Try(seams.SpecID)
  local forClass, forSpec = false, false
  for _, id in ipairs(specs) do
    if ofClass[id] then forClass = true end
    if okS and id == current then forSpec = true end
  end
  if not forClass then return false, nil end
  if not okS or type(current) ~= "number" then return true, nil end
  return true, forSpec
end

-- info: the slot's C_Container.GetContainerItemInfo table
function Facts.Read(bag, slot, info)
  if type(info) ~= "table" then return nil end
  local link, itemID = info.hyperlink, info.itemID
  local facts = {
    itemID = itemID, link = link, count = info.stackCount, icon = info.iconFileID,
    quality = info.quality, openable = info.hasLoot == true, hasNoValue = info.hasNoValue == true,
    name = info.itemName,
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
    if Facts.IsStatGear(facts) then GearFacts(facts, loc, link) end
    facts.usable, facts.hasUse = Facts.Usable(link)
    facts.accountBound = facts.warbound or Facts.AccountBound(link, facts.bindType)
    ClassFacts(facts, bag, slot, link)
  end
  return facts
end

-- usable, hasUse: whether this character can use the Use spell (the game's
-- own answer; nil when it can't be read, never taken as "no": FACT-01), and
-- whether the item has one
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
