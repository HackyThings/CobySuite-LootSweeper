-------------------------------------------------------------------------------
-- Fences: while anything but looting could put items in the bags, arrivals
-- never join the pile (design section 5)
--
-- A fence is up while any player-interaction window is open (vendor,
-- mailbox, trade, bank, warband bank, auction house, quest giver, gossip and
-- the rest of Enum.PlayerInteractionType), while the profession window is
-- open, and for a short tail after any of them closes or a quest is turned
-- in, so items that land a moment later are still fenced. The tail outlasts
-- the reconcile delay (Runs), so the read that sees those items is fenced.
-- A fence also leaves an exclusion that only a complete read taken once the
-- fence and its tail are over clears (ConsumeIfSettled): when reads fail for
-- longer than the tail, the arrivals are still fenced on the read that
-- finally sees them. When a tail runs out, the tail callback (Runs) asks for
-- that read, so the next loot is never the one it catches.
--
-- Container sessions: a loot window opened from an item (LOOT_OPENED with
-- isFromItem) opens a Ledger container session; a moment after the loot
-- window closes, onClose runs with the session still open, and only a
-- complete read there ends it (EndContainer).
--
-- Fences also keep the vendor and auction house open flags the seller and
-- the window read.
-------------------------------------------------------------------------------
local Fences = {}
CobysLootSweeper.Fences = Fences

Fences.TAIL = 2.0            -- seconds a fence stays up after it closes
Fences.CONTAINER_TAIL = 1.5  -- seconds after LOOT_CLOSED before a container session ends

local seams = {
  Now = function() return GetTime() end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
}
Fences._test = { seams = seams }

local open = {}          -- [key] = true while that window is open
local tailUntil = 0
local exclusion = false  -- a fence happened; cleared by a complete settled read
local onTailEnd = nil
local containerOpen = false
local containerCloseToken = 0
local merchantOpen, auctionOpen = false, false
local windowAt = -math.huge   -- when a window last opened or closed

local function Fire(kind, isOpen)
  CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.InteractionChanged, kind, isOpen)
end

local function StartTail()
  tailUntil = math.max(tailUntil, seams.Now() + Fences.TAIL)
  exclusion = true
  seams.After(Fences.TAIL + 0.1, function() if onTailEnd then onTailEnd() end end)
end

local function SetOpen(key, isOpen)
  windowAt = seams.Now()
  if isOpen then
    open[key] = true
    exclusion = true
  elseif open[key] then
    open[key] = nil
    StartTail()
  end
end

local function Settled()
  return next(open) == nil and seams.Now() >= tailUntil
end

function Fences.IsFenced()
  return exclusion or not Settled()
end

-- After a complete read: once nothing is open and the tail is over, the
-- fence has been seen by a read and is done
function Fences.ConsumeIfSettled()
  if Settled() then exclusion = false end
end

function Fences.SetTailCallback(fn) onTailEnd = fn end

function Fences.IsContainerOpen() return containerOpen end
-- The fences' clock, and whether a window that can take an item (vendor,
-- mail, trade, bank, AH...) is open or opened or closed since a moment of
-- that clock (Loot Sweeper's own fence pulse is no window)
function Fences.Now() return seams.Now() end
function Fences.WindowSince(at) return next(open) ~= nil or windowAt >= (at or 0) end
function Fences.IsMerchantOpen() return merchantOpen end
function Fences.IsAuctionOpen() return auctionOpen end

-- The open fences, for the Check Sweep report (test-only)
function Fences._test.OpenFences()
  local keys = {}
  for key in pairs(open) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)
  return keys
end

-------------------------------------------------------------------------------
-- Event handlers (Runs owns the event frame and forwards them)
-------------------------------------------------------------------------------
local INTERACTION = Enum and Enum.PlayerInteractionType or {}

function Fences.OnInteraction(interactionType, isOpen)
  SetOpen("interaction:" .. tostring(interactionType), isOpen)
  if interactionType == INTERACTION.Merchant and merchantOpen ~= isOpen then
    merchantOpen = isOpen
    Fire("merchant", isOpen)
  elseif interactionType == INTERACTION.Auctioneer and auctionOpen ~= isOpen then
    auctionOpen = isOpen
    Fire("auction", isOpen)
  end
end

local WINDOW_EVENTS = {
  MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
  TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
  AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
  BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
  QUEST_DETAIL = { "quest", true }, QUEST_PROGRESS = { "quest", true },
  QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
  TRADE_SKILL_SHOW = { "profession", true }, TRADE_SKILL_CLOSE = { "profession", false },
}
Fences.WINDOW_EVENTS = WINDOW_EVENTS

function Fences.OnWindowEvent(event)
  local spec = WINDOW_EVENTS[event]
  if not spec then return end
  local key, isOpen = spec[1], spec[2]
  SetOpen(key, isOpen)
  if key == "merchant" and merchantOpen ~= isOpen then
    merchantOpen = isOpen
    Fire("merchant", isOpen)
  elseif key == "auction" and auctionOpen ~= isOpen then
    auctionOpen = isOpen
    Fire("auction", isOpen)
  end
end

-- A quest reward or anything else that arrives without a window
function Fences.Pulse()
  StartTail()
end

-- LOOT_OPENED: a loot window from an item starts a container session
function Fences.OnLootOpened(isFromItem, state)
  if not isFromItem then return end
  containerOpen = true
  containerCloseToken = containerCloseToken + 1
  CobysLootSweeper.Ledger.OpenContainerSession(state)
end

-- LOOT_CLOSED: onClose(token) runs once the bags have settled, with the
-- session still open; it calls EndContainer after a complete read
function Fences.OnLootClosed(onClose)
  if not containerOpen then return end
  containerCloseToken = containerCloseToken + 1
  local token = containerCloseToken
  seams.After(Fences.CONTAINER_TAIL, function()
    if token ~= containerCloseToken then return end
    onClose(token)
  end)
end

-- Is this close still the current one (no new loot window since)?
function Fences.IsContainerToken(token) return containerOpen and token == containerCloseToken end

function Fences.EndContainer()
  containerOpen = false
  containerCloseToken = containerCloseToken + 1
end

-- Save() / Restore(saved): every fence and the vendor and auction flags, so
-- a suite that resets them leaves the real state as it found it (a test run
-- at a vendor must not leave the addon thinking the vendor closed)
function Fences._test.Save()
  local copy = {}
  for key in pairs(open) do copy[key] = true end
  return { open = copy, tailUntil = tailUntil, exclusion = exclusion, containerOpen = containerOpen,
           containerCloseToken = containerCloseToken, merchantOpen = merchantOpen, auctionOpen = auctionOpen,
           windowAt = windowAt }
end
function Fences._test.Restore(saved)
  open = {}
  for key in pairs(saved.open or {}) do open[key] = true end
  tailUntil, exclusion, containerOpen = saved.tailUntil, saved.exclusion, saved.containerOpen
  -- The exact token: a real container close queued before the test still
  -- matches it, and the test's own closes ran on its scripted timer only
  containerCloseToken = saved.containerCloseToken or containerCloseToken
  merchantOpen, auctionOpen = saved.merchantOpen, saved.auctionOpen
  windowAt = saved.windowAt or windowAt
end

-- Tests and a login reset every flag
function Fences.Reset()
  open = {}
  tailUntil = 0
  exclusion = false
  containerOpen = false
  containerCloseToken = containerCloseToken + 1
  merchantOpen, auctionOpen = false, false
  windowAt = -math.huge
end
