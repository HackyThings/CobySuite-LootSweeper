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
-- A close that never comes can't hold a fence up for good (Task #109: one
-- left up from before The Stonevault kept a whole dungeon's loot out of the
-- pile). Before each read, Heal asks the game about every open interaction
-- (C_PlayerInteractionManager.IsInteractingWithNpcOfType) and the profession
-- window about its own frame; a loading screen closes the rest. Each of
-- those closes the usual way, tail and exclusion included.
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
  -- Is the player still at an NPC of this interaction type? nil when the
  -- game can't say
  IsInteracting = function(kind)
    local api = C_PlayerInteractionManager
    if not (api and api.IsInteractingWithNpcOfType) then return nil end
    local ok, interacting = pcall(api.IsInteractingWithNpcOfType, kind)
    if not ok or CobySuite_CobysLootSweeper.Utilities.IsSecret(interacting) then return nil end
    return interacting == true
  end,
  -- Is the profession window shown? nil before Blizzard_Professions loads
  ProfessionShown = function()
    local frame = ProfessionsFrame
    if not (frame and frame.IsShown) then return nil end
    return frame:IsShown() == true
  end,
  Log = function(fmt, ...) CobysLootSweeper.Debug.Log("TRACK", fmt, ...) end,
}
Fences._test = { seams = seams }

local open = {}          -- [key] = when that window opened, while it is open
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

-------------------------------------------------------------------------------
-- What each fence is called, for the log and the window ("Paused while
-- <label> is open")
-------------------------------------------------------------------------------
local INTERACTION = Enum and Enum.PlayerInteractionType or {}

local KEY_LABELS = {
  merchant = "a vendor", mail = "the mailbox", trade = "a trade", auction = "the auction house",
  bank = "the bank", quest = "a quest window", profession = "the profession window",
}
local TYPE_LABELS = {
  TradePartner = "a trade", Gossip = "a conversation", QuestGiver = "a quest window", Merchant = "a vendor",
  Vendor = "a vendor", Banker = "the bank", CharacterBanker = "the bank", AccountBanker = "the warband bank",
  GuildBanker = "the guild bank", VoidStorageBanker = "void storage", MailInfo = "the mailbox",
  Auctioneer = "the auction house", BlackMarketAuctioneer = "the Black Market", TaxiNode = "a flight map",
}

-- The interaction type a key stands for, or nil for a named window
local function KindOf(key)
  return tonumber(tostring(key):match("^interaction:(%-?%d+)$") or "")
end

function Fences.Label(key)
  if KEY_LABELS[key] then return KEY_LABELS[key] end
  local kind = KindOf(key)
  for name, value in pairs(INTERACTION) do
    if value == kind then
      if TYPE_LABELS[name] then return TYPE_LABELS[name] end
      -- "ItemUpgrade" reads "the item upgrade window"
      return "the " .. name:gsub("(%l)(%u)", "%1 %2"):lower() .. " window"
    end
  end
  return "a window"
end

local paused = nil   -- the label the window last showed

-- Paused(): the label of the window open longest, or nil with none open
function Fences.Paused()
  local first, at = nil, math.huge
  for key, since in pairs(open) do
    if since < at or (since == at and tostring(key) < tostring(first)) then first, at = key, since end
  end
  return first and Fences.Label(first) or nil
end

-- The window repaints only when what it would say changes
local function NotePaused()
  local now = Fences.Paused()
  if now == paused then return end
  paused = now
  CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.InteractionChanged, "fence", now ~= nil)
end

local function SetOpen(key, isOpen, why)
  windowAt = seams.Now()
  if isOpen then
    if not open[key] then
      open[key] = seams.Now()
      seams.Log("Fence up: %s (%s)", Fences.Label(key), tostring(key))
    end
    exclusion = true
  elseif open[key] then
    open[key] = nil
    StartTail()
    seams.Log("Fence down: %s (%s)%s", Fences.Label(key), tostring(key), why and (", " .. why) or "")
  end
  NotePaused()
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

-- OpenList(): every open fence, oldest first, with what the game says now
-- (true or false, nil when it can't say), for diag and Check Sweep
local function GameSays(key)
  local kind = KindOf(key)
  if kind then return seams.IsInteracting(kind) end
  if key == "profession" then return seams.ProfessionShown() end
  return nil
end

function Fences.OpenList()
  local now, list = seams.Now(), {}
  for key, since in pairs(open) do
    list[#list + 1] = { key = tostring(key), label = Fences.Label(key), age = math.floor(now - since), since = since,
                        game = GameSays(key) }
  end
  table.sort(list, function(a, b) return a.age > b.age or (a.age == b.age and a.key < b.key) end)
  return list
end

-------------------------------------------------------------------------------
-- Event handlers (Runs owns the event frame and forwards them)
-------------------------------------------------------------------------------
function Fences.OnInteraction(interactionType, isOpen, why)
  SetOpen("interaction:" .. tostring(interactionType), isOpen, why)
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
  -- A quest offer (QUEST_DETAIL) is no fence: accepting gives at most the
  -- quest's own items, which stay protected, while a boss's quest-starter
  -- item opens its offer the moment its loot lands (Kael'thas's Verdant
  -- Sphere, 2026-10-01: seven drops went unclaimed). Turn-ins still fence
  QUEST_PROGRESS = { "quest", true },
  QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
  TRADE_SKILL_SHOW = { "profession", true }, TRADE_SKILL_CLOSE = { "profession", false },
}
Fences.WINDOW_EVENTS = WINDOW_EVENTS

function Fences.OnWindowEvent(event, why)
  local spec = WINDOW_EVENTS[event]
  if not spec then return end
  local key, isOpen = spec[1], spec[2]
  SetOpen(key, isOpen, why)
  if key == "merchant" and merchantOpen ~= isOpen then
    merchantOpen = isOpen
    Fire("merchant", isOpen)
  elseif key == "auction" and auctionOpen ~= isOpen then
    auctionOpen = isOpen
    Fire("auction", isOpen)
  end
end

-- The event that closes each named window
local CLOSE_EVENT = {}
for event, spec in pairs(WINDOW_EVENTS) do
  if not spec[2] then CLOSE_EVENT[spec[1]] = event end
end

local function Close(key, why)
  local kind = KindOf(key)
  if kind then
    Fences.OnInteraction(kind, false, why)
  elseif CLOSE_EVENT[key] then
    Fences.OnWindowEvent(CLOSE_EVENT[key], why)
  end
end

-- Heal(): every open fence the game says is closed closes now, with its
-- tail; one it can't answer for stays up. Returns the labels of those closed
function Fences.Heal(why)
  local closed = {}
  for key in pairs(open) do
    if GameSays(key) == false then closed[#closed + 1] = key end
  end
  local labels = {}
  for _, key in ipairs(closed) do
    labels[#labels + 1] = Fences.Label(key)
    Close(key, why or "the game says it closed")
  end
  return labels
end

-- A loading screen (not a login or /reload, which reset everything) closes
-- every named window but the profession window, which answers for itself
function Fences.OnLoadingScreen()
  local named = {}
  for key in pairs(open) do
    if not KindOf(key) and key ~= "profession" then named[#named + 1] = key end
  end
  for _, key in ipairs(named) do Close(key, "loading screen") end
  Fences.Heal("loading screen")
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
  for key, since in pairs(open) do copy[key] = since end
  return { open = copy, tailUntil = tailUntil, exclusion = exclusion, containerOpen = containerOpen,
           containerCloseToken = containerCloseToken, merchantOpen = merchantOpen, auctionOpen = auctionOpen,
           windowAt = windowAt }
end
function Fences._test.Restore(saved)
  open = {}
  for key, since in pairs(saved.open or {}) do open[key] = type(since) == "number" and since or seams.Now() end
  tailUntil, exclusion, containerOpen = saved.tailUntil, saved.exclusion, saved.containerOpen
  -- The exact token: a real container close queued before the test still
  -- matches it, and the test's own closes ran on its scripted timer only
  containerCloseToken = saved.containerCloseToken or containerCloseToken
  merchantOpen, auctionOpen = saved.merchantOpen, saved.auctionOpen
  windowAt = saved.windowAt or windowAt
  NotePaused()
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
  NotePaused()
end
