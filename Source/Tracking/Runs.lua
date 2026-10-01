-------------------------------------------------------------------------------
-- Runs: when a run starts and ends, and the reads that feed the Ledger
--
-- A run starts by itself on entering a dungeon or raid from a past expansion
-- (Instance.Evaluate) and ends on leaving it; Start and Stop run one by hand
-- anywhere. Stopping inside an eligible instance keeps it from starting again
-- until the next entry. A run always starts after a complete read, so what
-- the player carries at that moment is the baseline (design section 3).
--
-- Every bag change schedules one read (Coalesce). The first read after a
-- login or /reload is a resync (Ledger): nothing counts as new loot. Logging
-- in inside the instance of a saved automatic run carries on with it;
-- logging in inside an eligible instance with no saved run starts one from
-- that moment, and the notice says loot from before is left alone.
--
-- Per-character state lives in COBYS_LOOT_SWEEPER_CHAR:
--   ledger     the Ledger state
--   run        the active run { id, kind = "auto" | "manual", name,
--              instanceMapID, startedAt } or nil
--   runs       [id] = { name, kind, startedAt, endedAt } for the active run
--              and runs that still have items in the pile or away
--   nextRunId, suppressedMapID
--   diag       counters for the Check Sweep report
--   history    History.lua's records and totals
--   reviewedAt when the window last showed (the vendor button's shimmer)
-------------------------------------------------------------------------------
local Runs = {}
CobysLootSweeper.Runs = Runs

local Ledger = CobysLootSweeper.Ledger
local Fences = CobysLootSweeper.Fences
local Bags = CobysLootSweeper.Bags
local Instance = CobysLootSweeper.Instance
local Events = CobysLootSweeper.Events
local Utilities = CobysLootSweeper.Utilities

Runs.RECONCILE_DELAY = 0.3
Runs.RETRY_DELAY = 1.0
Runs.MAX_VETOES = 3      -- reads in a row held back by MissesCarried before one is let through

local seams = {
  Time = function() return time() end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  ZoneName = function() return GetRealZoneText and GetRealZoneText() or nil end,
  Message = function(text) Utilities.Message(text) end,
  Read = function(extra) return Bags.Read(extra) end,
  StillCarried = function(guid) return Bags.StillCarried(guid) end,
}
Runs._test = { seams = seams }

local resyncPending = true
local pendingStart = nil
local preparing = false
local retryScheduled = false
local vetoes = 0
local expect = nil   -- a token used from Loot Sweeper: what it gives joins its run

Runs.CONVERSION_WAIT = 10   -- seconds a used token's item may take to arrive

local function Debug() return CobysLootSweeper.Debug end
local function Bus() return CobysLootSweeper.EventBus end

-------------------------------------------------------------------------------
-- Saved state
-------------------------------------------------------------------------------
local function NewChar()
  return { ledger = Ledger.NewState(), runs = {}, nextRunId = 1, diag = {} }
end

function Runs.InitializeData()
  local char = COBYS_LOOT_SWEEPER_CHAR
  if type(char) ~= "table" then char = NewChar() end
  char.ledger = Ledger.Normalize(char.ledger)
  char.ledger.container = nil   -- a loot window never stays open across a reload
  if type(char.runs) ~= "table" then char.runs = {} end
  if not Utilities.IsPositiveInteger(char.nextRunId) then char.nextRunId = 1 end
  if char.run ~= nil and (type(char.run) ~= "table" or type(char.run.id) ~= "number") then char.run = nil end
  if type(char.diag) ~= "table" then char.diag = {} end
  if type(char.suppressedMapID) ~= "number" then char.suppressedMapID = nil end
  COBYS_LOOT_SWEEPER_CHAR = char
  resyncPending = true
end

function Runs.Char()
  if type(COBYS_LOOT_SWEEPER_CHAR) ~= "table" then Runs.InitializeData() end
  return COBYS_LOOT_SWEEPER_CHAR
end

function Runs.Ledger() return Runs.Char().ledger end
function Runs.Active() return Runs.Char().run end
function Runs.IsPreparing() return preparing end

function Runs.RunName(runId)
  local info = runId and Runs.Char().runs[runId]
  return info and info.name or nil
end

-- Info(runId): { name, kind, startedAt, endedAt } of a run with loot waiting
function Runs.Info(runId)
  return runId and Runs.Char().runs[runId] or nil
end

-------------------------------------------------------------------------------
-- Reading
-------------------------------------------------------------------------------
local function KnownItemIDs(ledger)
  local ids = {}
  for _, known in pairs(ledger.known) do ids[known.itemID] = true end
  return ids
end

local function LogChanges(changes)
  local d = Debug()
  for _, c in ipairs(changes.claimed) do d.Log("TRACK", "Claimed %s x%d (%s)", tostring(c.itemID), c.units, c.why) end
  for _, c in ipairs(changes.held) do d.Log("TRACK", "Held %s x%d (%s)", tostring(c.itemID), c.units, c.why) end
  for _, c in ipairs(changes.released) do d.Log("TRACK", "Released %s x%d (%s)", tostring(c.itemID), c.units, c.why) end
  for _, c in ipairs(changes.pending) do d.Log("TRACK", "Waiting on container: %s x%d", tostring(c.itemID), c.units) end
  for _, c in ipairs(changes.away) do d.Log("TRACK", "Away %s x%d (%s)", tostring(c.itemID), c.units, c.why) end
end

-- The changes without the release of a token being used from Loot Sweeper:
-- the fenced read that sees it leave would close its history record as
-- "left"; SettleConversion closes it as "used" instead
local function WithoutRelease(changes, guid)
  if not guid then return changes end
  local copy = {}
  for k, v in pairs(changes) do copy[k] = v end
  local kept = {}
  for _, c in ipairs(changes.released or {}) do
    if c.guid ~= guid then kept[#kept + 1] = c end
  end
  copy.released = kept
  return copy
end

local function HasChanges(changes)
  return #changes.claimed + #changes.held + #changes.released + #changes.pending + #changes.away > 0
end

-- A complete read that lacks a bag item the game still places in a carried
-- bag is not complete (zoning can hand out such a read)
local function MissesCarried(ledger, read)
  for guid, known in pairs(ledger.known) do
    if known.place == "bag" and not read.items[guid] and seams.StillCarried(guid) then return true end
  end
  return false
end

local BeginRun   -- defined below

local function ScheduleRetry()
  if retryScheduled then return end
  retryScheduled = true
  seams.After(Runs.RETRY_DELAY, function()
    retryScheduled = false
    Runs.RequestReconcile()
  end)
end

-- Reconcile(): one read into the ledger; false when the read was incomplete
function Runs.Reconcile()
  local char = Runs.Char()
  local read = seams.Read(KnownItemIDs(char.ledger))
  -- A few reads in a row only: if the game keeps placing an item no read
  -- finds, the read goes through and the away list keeps the loot
  local complete, reason = read.complete, read.reason
  if complete and MissesCarried(char.ledger, read) then
    vetoes = vetoes + 1
    if vetoes <= Runs.MAX_VETOES then
      complete, reason = false, "an item the game still places in a bag was missing"
    else
      Debug().Log("TRACK", "A carried item stayed missing from %d reads; reading on", vetoes - 1)
      vetoes = 0
    end
  else
    vetoes = 0
  end
  if not complete then
    Debug().Log("TRACK", "Read incomplete (%s), trying again", tostring(reason))
    if pendingStart and not preparing then
      preparing = true
      Bus():Fire(Events.RunChanged)
    end
    ScheduleRetry()
    return false
  end
  local run = char.run
  local ctx = {
    runActive = run ~= nil, runId = run and run.id, fenced = Fences.IsFenced(),
    resync = resyncPending, containerOpen = Fences.IsContainerOpen(), now = seams.Time(),
  }
  local before = { known = char.ledger.known, owned = char.ledger.owned }
  local changes = Ledger.Reconcile(char.ledger, read, ctx)
  local expecting = Runs.NoteTokenLeft(read, before)
  Runs.SettleConversion(char, read, before, ctx.now)
  Fences.ConsumeIfSettled()
  if resyncPending then Debug().Log("TRACK", "Resync read done") end
  resyncPending = false
  if HasChanges(changes) then
    LogChanges(changes)
    CobysLootSweeper.History.OnChanges(WithoutRelease(changes, expecting), char.ledger, ctx.now)
    Bus():Fire(Events.PileChanged)
  end
  if ctx.resync then Runs.RescueFromHistory(char, read) end
  if pendingStart then
    local p = pendingStart
    pendingStart = nil
    preparing = false
    BeginRun(p)
  end
  return true
end

local reconcileTimer = CobySuite_CobysLootSweeper.Utilities.Coalesce(Runs.RECONCILE_DELAY, function() Runs.Reconcile() end)

function Runs.RequestReconcile()
  reconcileTimer:Call()
end

-- A token of a run is about to be used from Loot Sweeper's Use Token window
function Runs.ExpectConversion(guid)
  local char = Runs.Char()
  local entry = guid and char.ledger.pile[guid]
  if not entry then
    expect = nil
    return false
  end
  local known = char.ledger.known[guid]
  local count = known and known.count or entry.count or 1
  -- A token stack that isn't wholly run loot gives a held piece (TRACK-02)
  local hold = nil
  if not Ledger.IsSellable(char.ledger, guid, count) then hold = entry.hold or Ledger.HOLD_MIXED end
  expect = { guid = guid, itemID = entry.itemID, count = count, runId = entry.runId, at = entry.at, hold = hold,
             deadline = seams.Time() + Runs.CONVERSION_WAIT, since = Fences.Now() }
  Debug().Log("TRACK", "Expecting what token %s gives", tostring(entry.itemID))
  return true
end

-- After a read: the item a used token gave joins the token's run
-- The read the expected token leaves in: used when it left the character
-- (its owned total dropped) and no window that could take it opened or
-- closed since the Use click; banked, mailed, traded or sold (a window
-- since, even one already closed again, or the total held) is no use: the
-- expectation ends and History sees the release as usual. Loot Sweeper's Use
-- never fires with a vendor open, so a token gone at a vendor was sold.
-- Returns the GUID whose release History must not see (the conversion
-- closes it as "used"), or nil
function Runs.NoteTokenLeft(read, before)
  if not expect then return nil end
  if not expect.consumed and (before.known or {})[expect.guid] and not read.items[expect.guid] then
    local was = (before.owned or {})[expect.itemID]
    local now = (read.owned or {})[expect.itemID]
    if not Fences.WindowSince(expect.since) and type(was) == "number" and type(now) == "number" and now < was then
      expect.consumed = true
    else
      Debug().Log("TRACK", "Token %s left without being used", tostring(expect.itemID))
      expect = nil
      return nil
    end
  end
  return expect.consumed and expect.guid or nil
end

-- A token used (it left the character) is closed as "used" however its
-- piece turned out (claimed, unclear, or not seen in time); one still in the
-- bags stays open
function Runs.SettleConversion(char, read, before, now)
  if not expect then return end
  local History = CobysLootSweeper.History
  if (now or 0) > expect.deadline then
    Debug().Log("TRACK", "Nothing arrived from token %s in time", tostring(expect.itemID))
    if expect.consumed then History.Used(expect.guid, now) end
    expect = nil
    return
  end
  local changes, result = Ledger.ClaimConversion(char.ledger, read, before, expect)
  if not result then return end
  History.Used(expect.guid, now)
  if result == "claimed" then
    LogChanges(changes)
    History.OnChanges(changes, char.ledger, now)
    Bus():Fire(Events.PileChanged)
  else
    Debug().Log("TRACK", "Several new items after token %s; none claimed", tostring(expect.itemID))
  end
  expect = nil
end

-- After a login or /reload: run loot the history knows, still in the bags
-- but no longer in the pile (an older build released it), comes back, and
-- its run with it
function Runs.RescueFromHistory(char, read)
  local History = CobysLootSweeper.History
  local changes = Ledger.Rescue(char.ledger, read, History.OpenRecords())
  if #changes.claimed == 0 then return end
  for _, c in ipairs(changes.claimed) do
    local runId = char.ledger.pile[c.guid] and char.ledger.pile[c.guid].runId
    if runId and not char.runs[runId] then
      local info = History.RunInfo(runId) or {}
      char.runs[runId] = { name = info.name, kind = "auto", startedAt = info.startedAt, endedAt = info.endedAt or seams.Time() }
    end
  end
  LogChanges(changes)
  Bus():Fire(Events.PileChanged)
end

-------------------------------------------------------------------------------
-- Run lifecycle
-------------------------------------------------------------------------------
local function PruneRuns(char)
  local used = {}
  for _, list in ipairs({ char.ledger.pile, char.ledger.away }) do
    for _, entry in pairs(list) do
      if entry.runId then used[entry.runId] = true end
    end
  end
  for id, info in pairs(char.runs) do
    if info.endedAt and not used[id] and not (char.run and char.run.id == id) then char.runs[id] = nil end
  end
end

local function StartMessage(p, name)
  if p.kind == "manual" then
    return "Tracking started. Loot you pick up from now on can be swept; what you carry now is safe."
  end
  if p.fromLogin then
    return string.format("Tracking %s from now on. Loot you picked up before this point is left alone.", name)
  end
  return string.format("Tracking %s. Your existing items are safe.", name)
end

-- Is an automatic start still where it was asked for?
local function StillEligible(p)
  if p.kind ~= "auto" then return true end
  local now = Instance.Evaluate()
  return now.eligible and p.info ~= nil and now.instanceMapID == p.info.instanceMapID
end

BeginRun = function(p)
  local char = Runs.Char()
  if char.run then return end
  if not StillEligible(p) then
    Debug().Log("RUN", "Pending start dropped: no longer in %s", tostring(p.info and p.info.name))
    Bus():Fire(Events.RunChanged)
    return
  end
  local name = p.info and p.info.name or seams.ZoneName() or "Manual run"
  local id = char.nextRunId
  char.nextRunId = id + 1
  char.run = {
    id = id, kind = p.kind, name = name, startedAt = seams.Time(),
    instanceMapID = p.info and p.info.instanceMapID or nil,
  }
  char.runs[id] = { name = name, kind = p.kind, startedAt = char.run.startedAt }
  Debug().Log("RUN", "Run %d started (%s) in %s", id, p.kind, tostring(name))
  if CobysLootSweeper.Config.Get("announce") then seams.Message(StartMessage(p, name)) end
  Bus():Fire(Events.RunChanged)
end

local function Summary(name)
  local pile = CobysLootSweeper.Pile
  local s = pile and pile.Summary and pile.Summary()
  if not s or (s.vendor.count + s.post.count + s.keep.count) == 0 then
    return string.format("%s finished. No loot is waiting.", name)
  end
  local parts = {}
  if s.vendor.count > 0 then
    parts[#parts + 1] = string.format("%d to sell (%s)", s.vendor.count, Utilities.Money(s.vendor.value))
  end
  if s.post.count > 0 then parts[#parts + 1] = string.format("%d worth posting", s.post.count) end
  if s.keep.count > 0 then parts[#parts + 1] = string.format("%d kept", s.keep.count) end
  return string.format("%s finished. Waiting from all your runs: %s.", name, table.concat(parts, ", "))
end

function Runs.EndRun(why)
  local char = Runs.Char()
  local run = char.run
  if not run then return end
  Runs.Reconcile()   -- the last loot before leaving still counts
  char.run = nil
  if char.runs[run.id] then char.runs[run.id].endedAt = seams.Time() end
  CobysLootSweeper.History.RunEnded(run.id, seams.Time())
  PruneRuns(char)
  Debug().Log("RUN", "Run %d ended (%s)", run.id, tostring(why))
  Bus():Fire(Events.RunChanged)
  if CobysLootSweeper.Config.Get("announce") then
    local name = run.name or "The run"
    seams.After(1, function() seams.Message(Summary(name)) end)
  end
end

local function RequestStart(p)
  pendingStart = p
  Runs.RequestReconcile()
end

-- PLAYER_ENTERING_WORLD: start, carry on or end the automatic run
function Runs.OnEnteringWorld(isLogin, isReload)
  local char = Runs.Char()
  if isLogin or isReload then
    resyncPending = true
    Fences.Reset()
  end
  local info = Instance.Evaluate()
  Debug().Log("RUN", "Entered %s: eligible=%s (%s)", tostring(info.name), tostring(info.eligible), tostring(info.reason))
  if pendingStart and pendingStart.kind == "auto"
      and not (info.eligible and pendingStart.info and info.instanceMapID == pendingStart.info.instanceMapID) then
    pendingStart = nil
    preparing = false
    Bus():Fire(Events.RunChanged)
  end
  local run = char.run
  if run and run.kind == "auto" and not (info.eligible and info.instanceMapID == run.instanceMapID) then
    Runs.EndRun("left the instance")
    run = nil
  elseif run and (isLogin or isReload) and CobysLootSweeper.Config.Get("announce") then
    seams.Message(string.format("Still tracking %s.", run.name or "this run"))
  end
  if char.suppressedMapID and char.suppressedMapID ~= info.instanceMapID then char.suppressedMapID = nil end
  if not run and info.eligible and char.suppressedMapID ~= info.instanceMapID then
    RequestStart({ kind = "auto", info = info, fromLogin = isLogin or isReload })
  end
  Runs.RequestReconcile()
end

function Runs.StartManual()
  local char = Runs.Char()
  if char.run or pendingStart then
    seams.Message("A run is already being tracked.")
    return false
  end
  RequestStart({ kind = "manual" })
  return true
end

function Runs.Stop()
  local char = Runs.Char()
  if pendingStart then
    pendingStart = nil
    preparing = false
    Bus():Fire(Events.RunChanged)
    return true
  end
  if not char.run then
    seams.Message("No run is being tracked.")
    return false
  end
  local info = Instance.Evaluate()
  if info.eligible then char.suppressedMapID = info.instanceMapID end
  Runs.EndRun("stopped")
  return true
end

-- Forget remaining loot: the pile (or one run's part of it, runId; 0 for
-- loot with no run) empties; the items are just the player's
function Runs.Forget(runId)
  local char = Runs.Char()
  CobysLootSweeper.History.LetGo(runId, seams.Time())
  Ledger.Forget(char.ledger, runId)
  PruneRuns(char)
  Debug().Log("RUN", runId and ("Run " .. runId .. "'s loot forgotten") or "Pile forgotten")
  Bus():Fire(Events.PileChanged)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local function OnLootChat(text)
  local diag = Runs.Char().diag
  if Utilities.IsSecret(text) then
    diag.lootChatSecret = (diag.lootChatSecret or 0) + 1
  else
    diag.lootChatReadable = (diag.lootChatReadable or 0) + 1
  end
  local inInstance = IsInInstance and IsInInstance()
  if inInstance then diag.lootChatInInstance = (diag.lootChatInInstance or 0) + 1 end
end

-- The session ends only after a complete read taken with it still open;
-- an incomplete one tries again (a new loot window replaces this close)
local function OnContainerClosed(token)
  if not Fences.IsContainerToken(token) then return end
  if not Runs.Reconcile() then
    seams.After(Runs.RETRY_DELAY, function() OnContainerClosed(token) end)
    return
  end
  Fences.EndContainer()
  local char = Runs.Char()
  local run = char.run
  local changes = Ledger.CloseContainerSession(char.ledger, { runId = run and run.id, now = seams.Time() })
  if HasChanges(changes) then
    LogChanges(changes)
    CobysLootSweeper.History.OnChanges(changes, char.ledger, seams.Time())
    Bus():Fire(Events.PileChanged)
  end
end

local handlers = {
  PLAYER_ENTERING_WORLD = function(isLogin, isReload) Runs.OnEnteringWorld(isLogin, isReload) end,
  BAG_UPDATE_DELAYED = function() Runs.RequestReconcile() end,
  PLAYER_EQUIPMENT_CHANGED = function() Runs.RequestReconcile() end,
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) Fences.OnInteraction(kind, true) end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind)
    Fences.OnInteraction(kind, false)
    Runs.RequestReconcile()
  end,
  QUEST_TURNED_IN = function() Fences.Pulse() end,
  LOOT_OPENED = function(_, isFromItem) Fences.OnLootOpened(isFromItem, Runs.Ledger()) end,
  LOOT_CLOSED = function() Fences.OnLootClosed(OnContainerClosed) end,
  CHAT_MSG_LOOT = function(text) OnLootChat(text) end,
}
for event in pairs(Fences.WINDOW_EVENTS) do
  handlers[event] = function() Fences.OnWindowEvent(event) end
end
Runs._test.handlers = handlers

Runs._test.OnContainerClosed = OnContainerClosed
-- Tests: set the module's own state (resync, pending start)
function Runs._test.SetState(opts)
  vetoes = 0
  expect = nil
  resyncPending = opts.resync == true
  pendingStart = opts.pendingStart
  preparing = false
  retryScheduled = false
end
function Runs._test.PendingStart() return pendingStart end
-- Save() / Restore(saved): the module's own state, so a suite that scripts
-- it leaves the real addon as it found it
function Runs._test.Save()
  return { resyncPending = resyncPending, pendingStart = pendingStart, preparing = preparing,
           retryScheduled = retryScheduled, vetoes = vetoes, expect = expect }
end
function Runs._test.Restore(saved)
  resyncPending, pendingStart, preparing = saved.resyncPending, saved.pendingStart, saved.preparing
  retryScheduled, vetoes, expect = saved.retryScheduled, saved.vetoes, saved.expect
end

-- When a fence's tail runs out, one read settles it
Fences.SetTailCallback(function() Runs.RequestReconcile() end)

local frame = CreateFrame("Frame")
for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler then handler(...) end
end)
