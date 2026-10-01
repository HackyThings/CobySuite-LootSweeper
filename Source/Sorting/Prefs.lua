-------------------------------------------------------------------------------
-- Prefs: the player's own choice for one copy or for every copy of an item
--
-- One copy: entry.pref on its pile entry ("keep" or "sell"), gone with the
-- entry. Every copy ("Remember for future copies"): the account-wide
-- COBYS_LOOT_SWEEPER_PREFS.items[itemID]. A copy's own choice wins over the
-- remembered one. Choosing Automatic clears both for that item. The rules
-- decide what a choice may change (Rules: hard protections always win).
-------------------------------------------------------------------------------
local Prefs = {}
CobysLootSweeper.Prefs = Prefs

Prefs.KEEP = "keep"
Prefs.SELL = "sell"

local VALID = { keep = true, sell = true }

function Prefs.InitializeData()
  local sv = COBYS_LOOT_SWEEPER_PREFS
  if type(sv) ~= "table" then sv = {} end
  if type(sv.items) ~= "table" then sv.items = {} end
  for itemID, value in pairs(sv.items) do
    if type(itemID) ~= "number" or not VALID[value] then sv.items[itemID] = nil end
  end
  COBYS_LOOT_SWEEPER_PREFS = sv
end

local function Items()
  if type(COBYS_LOOT_SWEEPER_PREFS) ~= "table" then Prefs.InitializeData() end
  return COBYS_LOOT_SWEEPER_PREFS.items
end

-- The choice for this entry, and whether it is remembered for the item
function Prefs.For(entry)
  if not entry then return nil end
  if VALID[entry.pref] then return entry.pref, false end
  local remembered = Items()[entry.itemID]
  if VALID[remembered] then return remembered, true end
  return nil
end

-- Set(entry, value, remember): value "keep", "sell" or nil (Automatic)
function Prefs.Set(entry, value, remember)
  if not entry then return end
  if value ~= nil and not VALID[value] then return end
  if value == nil then
    entry.pref = nil
    Items()[entry.itemID] = nil
  elseif remember then
    entry.pref = nil
    Items()[entry.itemID] = value
  else
    entry.pref = value
  end
  CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.PileChanged)
end
