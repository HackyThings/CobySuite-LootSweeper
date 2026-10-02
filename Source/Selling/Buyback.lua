-------------------------------------------------------------------------------
-- Buyback: run loot sold at a vendor by something other than Loot Sweeper
-- (the player's own right-click, Scrap) is found in the vendor's buyback
-- list and closed in History as "sold elsewhere" with what it fetched
-- (Cobanyte, 2026-10-01: count it, labelled)
--
-- Each vendor visit is a session. The buyback list is read when the vendor
-- opens (the baseline: older sales, even of the same item, never match) and
-- after every read while the session lasts; what appeared since is new. Run
-- loot that leaves the bags in the session (a "gone" release; History has
-- closed it as "left") waits for a new entry with its item ID and count,
-- whichever comes first, and Loot Sweeper's own sales use up their entries
-- the same way, so one can't stand in for a hand sale of the same item. The
-- list holds the last 12 sales: anything past that stays "left".
-------------------------------------------------------------------------------
local Buyback = {}
CobysLootSweeper.Buyback = Buyback

Buyback.SESSION_TAIL = 10   -- seconds after the vendor closes that a late entry still matches

local Utilities = CobysLootSweeper.Utilities
local Try, IsSecret = Utilities.Try, Utilities.IsSecret

-- GetNumBuybackItems and GetBuybackItemInfo are what Blizzard's live
-- MerchantFrame.lua reads the list with (not in the generated docs, and not
-- in any Blizzard_Deprecated* addon); the item ID comes from the documented
-- C_MerchantFrame.GetBuybackItemID. The price is the whole stack's, as the
-- vendor window shows it.
local seams = {
  Now = function() return GetTime() end,
  Num = function()
    local ok, n = Try(GetNumBuybackItems)
    if not ok or IsSecret(n) or type(n) ~= "number" then return nil end
    return n
  end,
  -- Entry(i) -> { itemID, quantity, price } or nil when unreadable
  Entry = function(i)
    local okID, itemID = Try(C_MerchantFrame and C_MerchantFrame.GetBuybackItemID, i)
    local okInfo, _, _, price, quantity = Try(GetBuybackItemInfo, i)
    if not (okID and okInfo) or IsSecret(itemID) or IsSecret(price) or IsSecret(quantity) then return nil end
    if type(itemID) ~= "number" or type(price) ~= "number" then return nil end
    return { itemID = itemID, quantity = type(quantity) == "number" and quantity or 1, price = price }
  end,
}
Buyback._test = { seams = seams }

local session = nil   -- { seen, fresh, waiting, closedAt }

-- The list as it stands, oldest first; nil when it can't be read whole
local function Read()
  local n = seams.Num()
  if not n then return nil end
  local list = {}
  for i = 1, n do
    local e = seams.Entry(i)
    if not e then return nil end
    list[i] = e
  end
  return list
end

local function Same(a, b)
  return a.itemID == b.itemID and a.quantity == b.quantity and a.price == b.price
end

-- What cur adds to prev: cur is prev less some oldest entries (the list
-- keeps 12), then the new ones at the end
local function Added(prev, cur)
  for drop = 0, #prev do
    local keep = #prev - drop
    local fits = keep <= #cur
    for j = 1, keep do
      if not fits then break end
      fits = Same(prev[drop + j], cur[j])
    end
    if fits then
      local out = {}
      for j = keep + 1, #cur do out[#out + 1] = cur[j] end
      return out
    end
  end
  return {}
end
Buyback._test.Added = Added

local function Active()
  if not session then return false end
  return not session.closedAt or seams.Now() - session.closedAt <= Buyback.SESSION_TAIL
end

-- The vendor opened (a new session from what the list holds now) or closed
function Buyback.OnMerchant(isOpen)
  if isOpen then
    session = { seen = Read() or {}, fresh = {}, waiting = {} }
  elseif session then
    session.closedAt = seams.Now()
  end
end

-- The first new entry for this item and count, taken out of the pool
local function Take(itemID, units)
  for i, e in ipairs(session.fresh) do
    if e.itemID == itemID and e.quantity == units then
      table.remove(session.fresh, i)
      return e
    end
  end
  return nil
end

-- After each read (Runs.Reconcile), with that read's releases; c.own is
-- what Loot Sweeper itself did to the item ("sold", "deleted", "used")
function Buyback.AfterRead(released)
  if not Active() then return end
  local cur = Read()
  if cur then
    for _, e in ipairs(Added(session.seen, cur)) do session.fresh[#session.fresh + 1] = e end
    session.seen = cur
  end
  for _, c in ipairs(released or {}) do
    if c.why == "gone" and (c.own == nil or c.own == "sold") then
      session.waiting[#session.waiting + 1] = { guid = c.guid, itemID = c.itemID, units = c.units, own = c.own }
    end
  end
  local still = {}
  for _, w in ipairs(session.waiting) do
    local e = Take(w.itemID, w.units)
    if not e then
      still[#still + 1] = w
    elseif not w.own then
      CobysLootSweeper.History.SoldElsewhere(w.guid, e.price)
    end
  end
  session.waiting = still
end

-- Tests: the session as it stands, and putting one back
function Buyback._test.Session() return session end
function Buyback._test.SetSession(s) session = s end

-- A vendor opening or closing starts or ends a session
local listener = {}
function listener:ReceiveEvent(_, kind, isOpen)
  if kind == "merchant" then Buyback.OnMerchant(isOpen) end
end
CobysLootSweeper.EventBus:Register(listener, { CobysLootSweeper.Events.InteractionChanged })
