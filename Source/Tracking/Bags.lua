-------------------------------------------------------------------------------
-- Bags: one complete read of the carried inventory, for the Ledger
--
-- Read(extraItemIDs) returns
--   { complete, reason, items = { [guid] = { itemID, count, link, place,
--       openable, bag, slot, quality, isBound, hasNoValue, isLocked } },
--     owned = { [itemID] = total with bank, reagent bank and warband bank } }
-- place is "bag" for the backpack, the four bags and the reagent bag, "equip"
-- for an equipped item. complete is false when any occupied slot came back
-- without its item ID, link or GUID, a call failed or a value was secret: an
-- unreadable read is never an empty one, so the caller skips it and tries
-- again (the rule Recollect's reader follows). extraItemIDs adds item IDs to
-- the owned totals (the ones in the last read, so a stack that left still
-- gets its new total). Every client call goes through Bags._test.seams.
-------------------------------------------------------------------------------
local Bags = {}
CobysLootSweeper.Bags = Bags

local Utilities = CobysLootSweeper.Utilities
local Try, IsSecret = Utilities.Try, Utilities.IsSecret

Bags.FIRST_BAG = 0          -- Enum.BagIndex.Backpack
Bags.LAST_BAG = 5           -- Enum.BagIndex.ReagentBag
Bags.FIRST_EQUIP = 1        -- INVSLOT_FIRST_EQUIPPED
Bags.LAST_EQUIP = 19        -- INVSLOT_LAST_EQUIPPED

local seams = {
  NumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end,
  SlotInfo = function(bag, slot) return C_Container.GetContainerItemInfo(bag, slot) end,
  BagGUID = function(bag, slot)
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    return C_Item.GetItemGUID(loc)
  end,
  EquipItem = function(slot)
    local loc = ItemLocation:CreateFromEquipmentSlot(slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    return C_Item.GetItemGUID(loc), C_Item.GetItemID(loc), C_Item.GetItemLink(loc)
  end,
  OwnedCount = function(itemID) return C_Item.GetItemCount(itemID, true, false, true, true) end,
  Location = function(guid)
    local loc = C_Item.GetItemLocation(guid)
    if not loc or not loc:IsBagAndSlot() then return nil end
    return loc:GetBagAndSlot()
  end,
}
Bags._test = { seams = seams }

local function Fail(read, why)
  read.complete = false
  read.reason = read.reason or why
end

local function ReadSlot(read, bag, slot)
  local ok, info = Try(seams.SlotInfo, bag, slot)
  if not ok then return Fail(read, "a bag slot could not be read") end
  if info == nil then return end
  if type(info) ~= "table" or Utilities.IsSecretTable(info) or IsSecret(info.itemID)
      or IsSecret(info.stackCount) or IsSecret(info.hyperlink) then
    return Fail(read, "a bag slot was hidden")
  end
  local okG, guid = Try(seams.BagGUID, bag, slot)
  if not okG or type(guid) ~= "string" or IsSecret(guid) or guid == "" then
    return Fail(read, "an item's identity was not ready")
  end
  if not Utilities.IsPositiveInteger(info.itemID) or type(info.hyperlink) ~= "string"
      or not Utilities.IsPositiveInteger(info.stackCount) then
    return Fail(read, "an item was still loading")
  end
  read.items[guid] = {
    itemID = info.itemID, count = info.stackCount, link = info.hyperlink, place = "bag",
    openable = info.hasLoot == true, bag = bag, slot = slot, quality = info.quality,
    isBound = info.isBound == true, hasNoValue = info.hasNoValue == true, isLocked = info.isLocked == true,
  }
end

local function ReadBags(read)
  for bag = Bags.FIRST_BAG, Bags.LAST_BAG do
    local ok, numSlots = Try(seams.NumSlots, bag)
    if not ok or IsSecret(numSlots) then
      Fail(read, "a bag could not be read")
    elseif type(numSlots) == "number" then
      for slot = 1, numSlots do ReadSlot(read, bag, slot) end
    end
  end
end

local function ReadEquipped(read)
  for slot = Bags.FIRST_EQUIP, Bags.LAST_EQUIP do
    local ok, guid, itemID, link = Try(seams.EquipItem, slot)
    if not ok or IsSecret(guid) or IsSecret(itemID) then
      Fail(read, "an equipped item could not be read")
    elseif guid ~= nil then
      if type(guid) ~= "string" or not Utilities.IsPositiveInteger(itemID) then
        Fail(read, "an equipped item was still loading")
      else
        read.items[guid] = { itemID = itemID, count = 1, link = link, place = "equip", equipSlot = slot }
      end
    end
  end
end

local function ReadOwned(read, extraItemIDs)
  local ids = {}
  for _, item in pairs(read.items) do ids[item.itemID] = true end
  for itemID in pairs(extraItemIDs or {}) do ids[itemID] = true end
  for itemID in pairs(ids) do
    local ok, total = Try(seams.OwnedCount, itemID)
    if not ok or IsSecret(total) or type(total) ~= "number" then
      Fail(read, "an item's total could not be read")
    else
      read.owned[itemID] = total
    end
  end
end

-- extraItemIDs: { [itemID] = true } (optional)
function Bags.Read(extraItemIDs)
  local read = { complete = true, items = {}, owned = {} }
  ReadBags(read)
  ReadEquipped(read)
  if read.complete then ReadOwned(read, extraItemIDs) end
  return read
end

-- True when the game places this GUID in a carried bag right now (false
-- when it doesn't, or can't say)
function Bags.StillCarried(guid)
  if type(guid) ~= "string" then return false end
  local ok, bag = Try(seams.Location, guid)
  return ok and type(bag) == "number" and bag >= Bags.FIRST_BAG and bag <= Bags.LAST_BAG
end

-- Where a GUID is right now: bag, slot and the slot's live info, or nil
function Bags.Locate(guid)
  if type(guid) ~= "string" then return nil end
  local ok, bag, slot = Try(seams.Location, guid)
  if not ok then return nil end
  if type(bag) ~= "number" or bag < Bags.FIRST_BAG or bag > Bags.LAST_BAG then return nil end
  local okI, info = Try(seams.SlotInfo, bag, slot)
  if not okI or type(info) ~= "table" or Utilities.IsSecretTable(info) then return nil end
  return bag, slot, info
end
