-------------------------------------------------------------------------------
-- Seller: sells the reviewed Vendor list at a vendor (design sections 3 and 8)
--
-- Start() takes the Vendor rows as they are on screen, cheapest first (so the
-- last 12, still in the vendor's buyback, are the most valuable), and sells
-- them one at a time. Before each sale the item is checked again: the vendor
-- is still open (C_Container.UseContainerItem would use the item otherwise),
-- no combat, the same GUID in a carried bag, the whole stack is still run
-- loot (Ledger.IsSellable), not locked, and the rules still say Vendor. An
-- item that fails is skipped. The next sale waits until the item has left
-- its slot; one that doesn't leave within TIMEOUT stops everything (a
-- Blizzard confirmation other than the trade question below, a refund
-- timer, a failed sale: never answered by us). A sale counts only once the
-- item is in no carried bag. Any other
-- item leaving the bags during the batch (checked before each sale and after
-- each one against the batch's starting bags) means another seller is at
-- work: stop. With "Pause after every 12 sales" on, it pauses after each
-- 12 and a click carries on. It never resumes by itself.
--
-- Loot a group member could still be traded asks the game's question ("you
-- could still trade this") when sold: the item waits on the cursor and the
-- game fires MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL. With skipTradeQuestion on
-- and that item the one this sale just used, SellCursorItem() finishes the
-- sale (the game's own popup closes once the cursor is empty; nothing of
-- Blizzard's is clicked). Off, the sale stops and says so.
--
-- Start(rows, opts): opts.onFinish(state) runs once the batch ends (the
-- one-at-a-time panel sells one row per Start). Each confirmed sale is
-- written to the History.
--
-- Status: Seller.State() = { phase = "idle" | "selling" | "paused" |
--   "stopped" | "done", sold, total, copper, skipped, message }
-------------------------------------------------------------------------------
local Seller = {}
CobysLootSweeper.Seller = Seller

local Bags = CobysLootSweeper.Bags
local Events = CobysLootSweeper.Events
local Utilities = CobysLootSweeper.Utilities

Seller.TIMEOUT = 3.0
Seller.STEP_DELAY = 0.2
Seller.POLL = 0.1
Seller.QUIET = 1.0
Seller.BATCH = 12

local seams = {
  Now = function() return GetTime() end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  InCombat = function() return InCombatLockdown() end,
  MerchantShown = function() return MerchantFrame ~= nil and MerchantFrame:IsShown() end,
  Use = function(bag, slot) C_Container.UseContainerItem(bag, slot) end,
  SlotGUID = function(bag, slot)
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    return C_Item.GetItemGUID(loc)
  end,
  NumSlots = function(bag) return C_Container.GetContainerNumSlots(bag) end,
  StopAfter12 = function() return CobysLootSweeper.Config.Get("stopAfter12") == true end,
  SkipTradeQuestion = function() return CobysLootSweeper.Config.Get("skipTradeQuestion") ~= false end,
  SellCursor = function() SellCursorItem() end,
  ClearCursor = function() ClearCursor() end,
}
Seller._test = { seams = seams }

local state = { phase = "idle", sold = 0, total = 0, copper = 0, skipped = 0 }
local queue = {}
local baseline = {}   -- the bag GUIDs at the batch's start, minus confirmed sales
local token = 0
local quietUntil = 0
local inFlight = nil  -- the target this sale just used, until it is confirmed
local onFinish = nil

local function Fire() CobysLootSweeper.EventBus:Fire(Events.SellChanged) end
local function Debug() return CobysLootSweeper.Debug end

function Seller.State() return state end
function Seller.IsBusy() return state.phase == "selling" end

-- The GUIDs in the carried bags right now
local function BagGUIDs()
  local set = {}
  for bag = Bags.FIRST_BAG, Bags.LAST_BAG do
    local ok, n = pcall(seams.NumSlots, bag)
    if ok and type(n) == "number" then
      for slot = 1, n do
        local okG, guid = pcall(seams.SlotGUID, bag, slot)
        if okG and type(guid) == "string" then set[guid] = true end
      end
    end
  end
  return set
end

function Seller.MerchantReady()
  return CobysLootSweeper.Fences.IsMerchantOpen() and seams.MerchantShown()
end

-- True once the vendor has been quiet for a second (another seller finished)
function Seller.IsQuiet()
  return seams.Now() >= quietUntil
end

function Seller.NoteBagActivity()
  if state.phase ~= "selling" and Seller.MerchantReady() then
    quietUntil = seams.Now() + Seller.QUIET
  end
end

function Seller.OnMerchantOpened()
  quietUntil = seams.Now() + Seller.QUIET
  state = { phase = "idle", sold = 0, total = 0, copper = 0, skipped = 0 }
  Fire()
end

-- Other addons that sell by themselves at a vendor
function Seller.OtherSellers()
  local names = {}
  if type(Scrap_Sets) == "table" and Scrap_Sets.sell then names[#names + 1] = "Scrap" end
  return names
end

-------------------------------------------------------------------------------
-- Stopping
-------------------------------------------------------------------------------
local function Plural(n, one, many) return n == 1 and one or many end

local function DoneMessage()
  local skipped = state.skipped > 0 and string.format(" %d skipped: look them over.", state.skipped) or ""
  return string.format("Done. Sold %d %s for %s.%s", state.sold, Plural(state.sold, "item", "items"),
    Utilities.Money(state.copper), skipped)
end

local function Finish(phase, message)
  token = token + 1
  queue = {}
  inFlight = nil
  state.phase = phase
  state.message = message
  local callback = onFinish
  onFinish = nil
  if callback then pcall(callback, state) end
  Debug().Log("SELL", "%s: %s (sold %d of %d, %s)", phase, tostring(message), state.sold, state.total,
    Utilities.Money(state.copper))
  Fire()
  CobysLootSweeper.Runs.RequestReconcile()
end

function Seller.Stop(message)
  if state.phase ~= "selling" and state.phase ~= "paused" then return end
  Finish("stopped", message or string.format("Stopped. Sold %d of %d.", state.sold, state.total))
end

-------------------------------------------------------------------------------
-- One sale
-------------------------------------------------------------------------------
-- The target as it is now: bag, slot, or nil and why it is skipped
local function Verify(target)
  local bag, slot, info = Bags.Locate(target.guid)
  if not bag then return nil, "gone" end
  if info.itemID ~= target.itemID or info.stackCount ~= target.count then return nil, "changed" end
  if info.isLocked then return nil, "locked" end
  local ledger = CobysLootSweeper.Runs.Ledger()
  if not CobysLootSweeper.Ledger.IsSellable(ledger, target.guid, info.stackCount) then return nil, "not run loot" end
  local entry = ledger.pile[target.guid]
  local facts = CobysLootSweeper.Facts.Read(bag, slot, info)
  if not facts then return nil, "unreadable" end
  local pref = CobysLootSweeper.Prefs.For(entry)
  local quote = CobysLootSweeper.Prices.Quote(facts.link)
  local result = CobysLootSweeper.Rules.Classify(entry, facts, quote, pref, CobysLootSweeper.Rules.Settings())
  if result.bucket ~= "vendor" then return nil, "no longer Vendor" end
  return bag, slot
end

local Step   -- forward

local EXTERNAL = "Your bags changed while selling, so it stopped. Look over what's left, then sell again."

-- True when an item the batch did not sell has left the bags
local function SomethingElseLeft(now)
  for guid in pairs(baseline) do
    if not now[guid] then return true end
  end
  return false
end

local function Confirmed(target, after, runToken)
  if runToken ~= token then return end
  inFlight = nil
  state.sold = state.sold + 1
  state.copper = state.copper + (target.value or 0)
  baseline[target.guid] = nil
  CobysLootSweeper.History.Sold(target.guid, target.value or 0)
  if SomethingElseLeft(after) then return Finish("stopped", EXTERNAL) end
  Fire()
  if #queue == 0 then return Finish("done", DoneMessage()) end
  if seams.StopAfter12() and state.sold % Seller.BATCH == 0 then
    token = token + 1
    state.phase = "paused"
    state.message = string.format("Paused after %d sales. Click to sell the next %d.", state.sold,
      math.min(Seller.BATCH, #queue))
    Fire()
    return
  end
  seams.After(Seller.STEP_DELAY, function() if runToken == token then Step() end end)
end

local NOT_SOLD = "A sale didn't go through, so selling stopped. Check your bags and any game window, then try again."

-- A sale counts only once the item is in no carried bag; still carried
-- (moved to another slot) means it was not sold
local function Await(target, bag, slot, runToken, deadline)
  if runToken ~= token then return end
  local ok, guid = pcall(seams.SlotGUID, bag, slot)
  if ok and guid ~= target.guid then
    local after = BagGUIDs()
    if after[target.guid] then return Finish("stopped", NOT_SOLD) end
    return Confirmed(target, after, runToken)
  end
  if seams.Now() >= deadline then return Finish("stopped", NOT_SOLD) end
  seams.After(Seller.POLL, function() Await(target, bag, slot, runToken, deadline) end)
end

Step = function()
  if state.phase ~= "selling" then return end
  if not Seller.MerchantReady() then return Finish("stopped", "Selling stopped: the vendor closed.") end
  if seams.InCombat() then return Finish("stopped", "Selling stopped for combat. Try again once it ends.") end
  local target = table.remove(queue, 1)
  if not target then return Finish("done", DoneMessage()) end
  local bag, slot = Verify(target)
  if not bag then
    state.skipped = state.skipped + 1
    Fire()
    return Step()
  end
  if SomethingElseLeft(BagGUIDs()) then return Finish("stopped", EXTERNAL) end
  local runToken = token
  -- Last check right before the call: never use an item without a vendor
  if not Seller.MerchantReady() then return Finish("stopped", "Selling stopped: the vendor closed.") end
  inFlight = { target = target, at = seams.Now(), inCall = true }
  local ok, err = pcall(seams.Use, bag, slot)
  if inFlight then inFlight.inCall = false end
  if not ok then
    Debug().Log("SELL", "The sale call failed: %s", tostring(err))
    return Finish("stopped", "The game didn't allow that sale. /ls debug has the details.")
  end
  Await(target, bag, slot, runToken, seams.Now() + Seller.TIMEOUT)
end

-------------------------------------------------------------------------------
-- Starting
-------------------------------------------------------------------------------
-- The game asks before selling loot a group member could still be traded.
-- The question is a synchronous event: for our sale it fires inside our own
-- UseContainerItem call. So it is answered only then, and only when it names
-- the item that call used; any other question (the player's own sale, another
-- addon's) is left to the game and the player (SELL-01)
local TRADE_QUESTION = "The game asked before selling an item you could still trade, so selling stopped. Turn on \"Sell loot you could still trade without asking\" in settings, or sell it by hand."
function Seller.OnTradeQuestion(link)
  if state.phase ~= "selling" or not inFlight or not inFlight.inCall then return false end
  local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if itemID ~= inFlight.target.itemID then return false end
  if not seams.SkipTradeQuestion() then
    pcall(seams.ClearCursor)
    Finish("stopped", TRADE_QUESTION)
    return false
  end
  Debug().Log("SELL", "Answered the trade question for %s", tostring(link))
  local ok = pcall(seams.SellCursor)
  return ok
end

-- rows: the Vendor rows as reviewed (Pile.Bucket("vendor")); opts.onFinish.
-- While paused, an empty rows list carries on with the paused batch, and new
-- rows replace it
function Seller.Start(rows, opts)
  if state.phase == "selling" then return false end
  if not Seller.MerchantReady() then return false end
  if seams.InCombat() then return false end
  if state.phase == "paused" and #queue > 0 and #(rows or {}) == 0 then
    token = token + 1
    baseline = BagGUIDs()
    state.phase = "selling"
    state.message = nil
    Fire()
    Step()
    return true
  end
  queue = {}
  for _, row in ipairs(rows or {}) do
    queue[#queue + 1] = {
      guid = row.guid, itemID = row.entry.itemID, count = row.facts.count,
      value = row.vendorValue or 0, name = row.facts.name,
    }
  end
  table.sort(queue, function(a, b)
    if a.value ~= b.value then return a.value < b.value end
    return (a.name or "") < (b.name or "")
  end)
  if #queue == 0 then return false end
  onFinish = opts and opts.onFinish or nil
  token = token + 1
  baseline = BagGUIDs()
  state = { phase = "selling", sold = 0, total = #queue, copper = 0, skipped = 0 }
  Debug().Log("SELL", "Selling %d entries", #queue)
  Fire()
  Step()
  return true
end

-------------------------------------------------------------------------------
-- Listeners
-------------------------------------------------------------------------------
local listener = {}
function listener:ReceiveEvent(event, kind, isOpen)
  if event ~= Events.InteractionChanged or kind ~= "merchant" then return end
  if isOpen then
    Seller.OnMerchantOpened()
  elseif state.phase == "selling" or state.phase == "paused" then
    Finish("stopped", "Selling stopped: the vendor closed.")
  end
end
CobysLootSweeper.EventBus:Register(listener, { Events.InteractionChanged })

local frame = CreateFrame("Frame")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" then
    Seller.OnTradeQuestion(...)
  elseif event == "PLAYER_REGEN_DISABLED" then
    if state.phase == "selling" then Finish("stopped", "Selling stopped for combat. Try again once it ends.") end
  else
    Seller.NoteBagActivity()
  end
end)
