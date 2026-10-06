-------------------------------------------------------------------------------
-- Runs: when a run starts and ends, and the reads that feed the Ledger
--
-- A run starts by itself on entering a dungeon or raid from a past expansion,
-- or a current-content place the player allowed (Runs.Tracked), and ends on
-- leaving it; Start and Stop run one by hand anywhere. Stopping inside an
-- eligible instance keeps it from starting again until the next entry. A run
-- always starts after a complete read, so what the player carries at that
-- moment is the baseline (design section 3).
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
--              instanceMapID, startedAt, once } or nil
--   runs       [id] = { name, kind, startedAt, endedAt } for the active run
--              and runs that still have items in the pile, away or ignored
--   nextRunId, suppressedMapID
--   keepsMoved true once the 0.0.1 one-copy Keeps were let go (Prefs: a
--              Keep now covers every copy of the item and hides it)
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
  Announce = function(info) CobysLootSweeper.TrackOffer.Announce(info) end,
  Locate = function(guid) return Bags.Locate(guid) end,
  ZoneMap = function() return C_Map.GetBestMapForUnit("player") end,
  MapName = function(uiMapID)
    local info = C_Map.GetMapInfo(uiMapID)
    return info and info.name
  end,
}
Runs._test = { seams = seams }

local resyncPending = true
local pendingStart = nil
local preparing = false
local retryScheduled = false
local vetoes = 0
local expect = nil   -- a token used from Loot Sweeper: what it gives joins its run
-- This visit's offer for current content: the instance, the offer made
-- (its info, or true once answered) and a "Yes, this time"
local visit = { mapID = nil, offered = nil, once = nil }

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
  Runs.MoveOldKeeps(char)
end

-- 0.0.1 kept one copy at a time (entry.pref = "keep", listed in Keep). A
-- Keep now covers the item and hides it, so those copies are let go once
-- (History: "kept"); a remembered Keep moved into the lists (Prefs).
function Runs.MoveOldKeeps(char)
  if char.keepsMoved then return end
  local changes = { claimed = {}, released = {}, held = {}, pending = {}, away = {} }
  for _, list in ipairs({ char.ledger.pile, char.ledger.away }) do
    for guid, entry in pairs(list) do
      if entry.pref == "keep" then
        list[guid] = nil
        changes.released[#changes.released + 1] = { guid = guid, itemID = entry.itemID,
          units = entry.count + entry.added, why = "kept" }
      end
    end
  end
  char.keepsMoved = true
  if #changes.released > 0 then
    CobysLootSweeper.History.OnChanges(changes, char.ledger, seams.Time())
    Debug().Log("TRACK", "Let go of %d copies kept one at a time before Keep covered every copy", #changes.released)
  end
end

-- Every step that can add to the pile ends here: an item the player keeps
-- never stays in it (Prefs.Keep)
local function WithoutKept(char, changes)
  return Ledger.DropKept(char.ledger, CobysLootSweeper.Prefs.IsKept, changes)
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

Runs.LOG_EACH = 6   -- a list longer than this is logged grouped by why

-- Logs a list of changes as "<verb> <id> x<units> (<why>)" per entry, or as
-- one line per why when the list is long
local function LogList(verb, list, whyOf)
  local d = Debug()
  if #list <= Runs.LOG_EACH then
    for _, c in ipairs(list) do d.Log("TRACK", "%s %s x%d (%s)", verb, tostring(c.itemID), c.units, whyOf(c)) end
    return
  end
  local groups, order = {}, {}
  for _, c in ipairs(list) do
    local why = whyOf(c)
    if not groups[why] then groups[why] = {}; order[#order + 1] = why end
    local g = groups[why]
    g[#g + 1] = tostring(c.itemID) .. " x" .. tostring(c.units)
  end
  for _, why in ipairs(order) do
    local g = groups[why]
    d.Log("TRACK", "%s %d stacks (%s): %s", verb, #g, why, table.concat(g, ", "))
  end
end

local function Why(c) return tostring(c.why) end

-- An item Loot Sweeper sold, deleted or used leaves under a fence like any
-- other; the log says which it was (the Molten Core log read "Released
-- (gone)" for every sale)
local function ReleaseWhy(c)
  return c.own and (c.own .. " by Loot Sweeper") or tostring(c.why)
end

-- Each "gone" release learns what Loot Sweeper itself did to it, for the log
-- and for Buyback
local function NoteOwn(changes)
  for _, c in ipairs(changes.released or {}) do
    if c.why == "gone" then c.own = CobysLootSweeper.History.TakeOwnOutcome(c.guid) end
  end
end

local function LogChanges(changes)
  LogList("Claimed", changes.claimed, Why)
  LogList("Held", changes.held, Why)
  LogList("Released", changes.released, ReleaseWhy)
  for _, c in ipairs(changes.pending) do Debug().Log("TRACK", "Waiting on container: %s x%d", tostring(c.itemID), c.units) end
  LogList("Away", changes.away, Why)
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

-- A fence the game says is gone closes before the read (Task #109); while
-- one holds a run's arrivals back, the log and Check Sweep name the window
local function FenceNotes(char)
  char.diag.fences = char.diag.fences or {}
  return char.diag.fences
end

local function HealFences(char)
  local healed = Fences.Heal()
  if #healed > 0 then
    FenceNotes(char).healed = { at = seams.Time(), windows = healed }
  end
end

local function NoteFenced(char, read, before, now)
  local count = 0
  for guid, item in pairs(read.items) do
    if item.place == "bag" and not (before.known or {})[guid] then count = count + 1 end
  end
  if count == 0 then return end
  local window = Fences.Paused() or "a window that just closed"
  Debug().Log("TRACK", "Not claimed (fenced by %s): %d new %s", window, count, count == 1 and "item" or "items")
  FenceNotes(char).skipped = { at = now, window = window, count = count, open = Fences.OpenList() }
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
  HealFences(char)
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
  local changes = WithoutKept(char, Ledger.Reconcile(char.ledger, read, ctx))
  if ctx.runActive and ctx.fenced then NoteFenced(char, read, before, ctx.now) end
  local expecting = Runs.NoteTokenLeft(read, before)
  Runs.SettleConversion(char, read, before, ctx.now)
  Fences.ConsumeIfSettled()
  if resyncPending then Debug().Log("TRACK", "Resync read done") end
  resyncPending = false
  NoteOwn(changes)
  if HasChanges(changes) then
    LogChanges(changes)
    CobysLootSweeper.History.OnChanges(WithoutRelease(changes, expecting), char.ledger, ctx.now)
    Bus():Fire(Events.PileChanged)
  end
  -- A vendor's buyback list names what was sold there by someone else
  CobysLootSweeper.Buyback.AfterRead(changes.released)
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
  changes = WithoutKept(char, changes)
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
  local changes = WithoutKept(char, Ledger.Rescue(char.ledger, read, History.OpenRecords()))
  if #changes.released > 0 then
    History.OnChanges(changes, char.ledger, seams.Time())
    Bus():Fire(Events.PileChanged)
  end
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
  for _, list in ipairs({ char.ledger.pile, char.ledger.away, char.ledger.ignored }) do
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

-- Tracked(info): does a run start by itself here? Old content, or current
-- content the player said yes to (always, or for this visit)
function Runs.Tracked(info)
  if info.eligible then return true end
  if not Instance.Offerable(info) then return false end
  local id = info.instanceMapID
  return CobysLootSweeper.Prefs.IsAllowed(id) or visit.once == id
end

-- Is an automatic start still where it was asked for?
local function StillEligible(p)
  if p.kind ~= "auto" then return true end
  local now = Instance.Evaluate()
  return Runs.Tracked(now) and p.info ~= nil and now.instanceMapID == p.info.instanceMapID
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
    once = p.once == true or nil,   -- "Yes, this time": kept across a /reload (RUN-01)
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
  if s.keep.count > 0 then parts[#parts + 1] = string.format("%d protected", s.keep.count) end
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
  -- A new place ends this visit's offer and its "Yes, this time"
  if visit.mapID ~= info.instanceMapID then visit.mapID, visit.offered, visit.once = info.instanceMapID, nil, nil end
  -- A /reload or login in the instance of a run started with "Yes, this
  -- time" is still that visit (review 2026-10-01, RUN-01)
  local saved = char.run
  if (isLogin or isReload) and saved and saved.once and saved.instanceMapID == info.instanceMapID then
    visit.once, visit.offered = info.instanceMapID, true
  end
  local here = Runs.Tracked(info)
  if pendingStart and pendingStart.kind == "auto"
      and not (here and pendingStart.info and info.instanceMapID == pendingStart.info.instanceMapID) then
    pendingStart = nil
    preparing = false
    Bus():Fire(Events.RunChanged)
  end
  local run = char.run
  if run and run.kind == "auto" and not (here and info.instanceMapID == run.instanceMapID) then
    Runs.EndRun("left the instance")
    run = nil
  elseif run and (isLogin or isReload) and CobysLootSweeper.Config.Get("announce") then
    seams.Message(string.format("Still tracking %s.", run.name or "this run"))
  end
  if char.suppressedMapID and char.suppressedMapID ~= info.instanceMapID then char.suppressedMapID = nil end
  if not run and here and char.suppressedMapID ~= info.instanceMapID and not Runs.BlockedHere(info) then
    RequestStart({ kind = "auto", info = info, fromLogin = isLogin or isReload })
  elseif not run then
    Runs.CheckOffer(info)
    -- A delve can say so only a moment after the loading screen
    seams.After(Runs.OFFER_RECHECK, function() Runs.CheckOffer() end)
  end
  Runs.RequestReconcile()
end

-------------------------------------------------------------------------------
-- Current content: offered, never started by itself (the all-content plan,
-- section 5). Once per visit, OFFER_DELAY seconds after the offer is
-- decided (past the chat that follows a loading screen, which buried the
-- first build's line in game, 2026-10-01), one chat line with the addon's
-- icon and a [Track this run] link, plus TrackOffer's chirp (and its toast,
-- only with offerToast on); the link opens the prompt, the toast asks in
-- place: Yes, always here / Yes, this time / No
-------------------------------------------------------------------------------
Runs.OFFER_RECHECK = 2
Runs.OFFER_DELAY = 6

function Runs.OfferLink(id)
  local U = CobySuite_CobysLootSweeper.Utilities
  return U.WrapColor(U.ColorToHex(U.Colors.INFO_BLUE),
    string.format("|Haddon:CobysLootSweeper:track:%d|h[Track this run]|h", id))
end

-- CheckOffer(info): offers to track current content once per visit
function Runs.CheckOffer(info)
  info = info or Instance.Evaluate()
  local char = Runs.Char()
  local id = info.instanceMapID
  if visit.mapID ~= id then visit.mapID, visit.offered, visit.once = id, nil, nil end
  if char.run or pendingStart or visit.offered or char.suppressedMapID == id then return end
  if not Instance.Offerable(info) or Runs.BlockedHere(info) then return end
  if CobysLootSweeper.Prefs.IsAllowed(id) then
    RequestStart({ kind = "auto", info = info })
    return
  end
  visit.offered = info
  Debug().Log("RUN", "Offering to track %s (%s)", tostring(info.name), tostring(id))
  seams.After(Runs.OFFER_DELAY, function()
    -- Answered, left or replaced meanwhile: nothing to say
    if Runs.OpenOffer(id) ~= info then return end
    -- Asked in chat by default; the link opens the three choices (Task #252)
    seams.Message(string.format("|T%s:16|t %s is this season's content, so Loot Sweeper isn't tracking it. Click %s to choose.",
      tostring(CobysLootSweeper.ICON), info.name or "This place", Runs.OfferLink(id)))
    seams.Announce(info)
  end)
end

-- The offer still open here, or nil (the link's id must match)
function Runs.OpenOffer(id)
  local offer = visit.offered
  if type(offer) ~= "table" or (id and offer.instanceMapID ~= id) then return nil end
  return offer
end

-- AnswerOffer(answer, asked): "always" (adds the place to the allow list),
-- "once" (this visit) or "no"; true when a run is on its way. asked: the
-- offer the prompt showed; a different one open now is left alone
function Runs.AnswerOffer(answer, asked)
  if CobysLootSweeper.Utilities.Guarded("track offer") then return false end
  local offer = Runs.OpenOffer()
  if not offer then return false end
  if asked ~= nil and asked ~= offer then
    seams.Message("That offer has run out. Loot Sweeper offers again when you next enter current content.")
    return false
  end
  visit.offered = true
  if answer == "no" then return false end
  local now = Instance.Evaluate()
  if now.instanceMapID ~= offer.instanceMapID then
    seams.Message(string.format("You've left %s, so there is no run to track.", offer.name or "that place"))
    return false
  end
  if answer == "always" then
    CobysLootSweeper.Prefs.Allow(offer.instanceMapID, offer.name)
  else
    visit.once = offer.instanceMapID
  end
  if Runs.Char().run or pendingStart then return false end
  RequestStart({ kind = "auto", info = now, once = answer ~= "always" })
  return true
end

function Runs.StartManual()
  local char = Runs.Char()
  if char.run or pendingStart then
    seams.Message("A run is already being tracked.")
    return false
  end
  local blocked = Runs.BlockedHere()
  if blocked then
    seams.Message(string.format("%s is on your blocked list, so Loot Sweeper won't track it. /ls kept lists what you blocked.",
      blocked.name or "This place"))
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
  if CobysLootSweeper.Utilities.Guarded("forget") then return end
  local char = Runs.Char()
  CobysLootSweeper.History.LetGo(runId, seams.Time())
  Ledger.Forget(char.ledger, runId)
  PruneRuns(char)
  Debug().Log("RUN", runId and ("Run " .. runId .. "'s loot forgotten") or "Pile forgotten")
  Bus():Fire(Events.PileChanged)
end

-- Releases from the pile reach History, the runs list and the window
local function SettleReleases(char, changes)
  if #changes.released == 0 then return end
  LogChanges(changes)
  CobysLootSweeper.History.OnChanges(changes, char.ledger, seams.Time())
  PruneRuns(char)
  Bus():Fire(Events.PileChanged)
end

-- Keep: the pile lets go of every item the player keeps (Prefs.Keep, an
-- import, the switch to account-wide lists)
function Runs.LetGoKept()
  local char = Runs.Char()
  SettleReleases(char, Ledger.DropKept(char.ledger, CobysLootSweeper.Prefs.IsKept))
end

-- Ignore these copies (the menu's Ignore): hidden until un-ignored, on the
-- window's Ignored tab
function Runs.Ignore(guids)
  if CobysLootSweeper.Utilities.Guarded("ignore") then return end
  local char = Runs.Char()
  SettleReleases(char, Ledger.Ignore(char.ledger, guids, seams.Time()))
end

-- Unignore(guid): an ignored copy back in the pile, its History record
-- waiting again; false (and a chat line) when it has left the bags
function Runs.Unignore(guid)
  if CobysLootSweeper.Utilities.Guarded("un-ignore") then return false end
  local char = Runs.Char()
  local entry = char.ledger.ignored[guid]
  if not entry then return false end
  local bag, _, info = seams.Locate(guid)
  local item = bag and type(info) == "table" and { itemID = info.itemID, count = info.stackCount, place = "bag" } or nil
  local back = Ledger.Unignore(char.ledger, guid, item)
  Bus():Fire(Events.PileChanged)
  if not back then
    seams.Message("That item isn't in your bags any more, so there is nothing to un-ignore.")
    return false
  end
  CobysLootSweeper.History.Reopen(guid)
  Runs._test.lastUnignored = guid   -- what Verify's ls.post.unignored checks
  if back.runId and not char.runs[back.runId] then
    local info = CobysLootSweeper.History.RunInfo(back.runId) or {}
    char.runs[back.runId] = { name = info.name or back.runName, kind = "auto", startedAt = info.startedAt,
                              endedAt = info.endedAt or seams.Time() }
  end
  return true
end

-- Ignored(): { { guid, entry } } of the ignored copies
function Runs.Ignored()
  local out = {}
  for guid, entry in pairs(Runs.Char().ledger.ignored) do out[#out + 1] = { guid = guid, entry = entry } end
  return out
end

-------------------------------------------------------------------------------
-- Blocked places
-------------------------------------------------------------------------------
-- Place(info): where the player stands, as a block names it: inside a
-- dungeon, raid or scenario its instance map ID, elsewhere the zone
-- { kind = "instances" | "zones", id, name }, or nil when it can't be read
function Runs.Place(info)
  info = info or Instance.Evaluate()
  local t = info.instanceType
  if (t == "party" or t == "raid" or t == "scenario") and type(info.instanceMapID) == "number" then
    return { kind = "instances", id = info.instanceMapID, name = info.name }
  end
  local ok, uiMapID = Utilities.Try(seams.ZoneMap)
  if not ok or type(uiMapID) ~= "number" or Utilities.IsSecret(uiMapID) then return nil end
  local okN, name = Utilities.Try(seams.MapName, uiMapID)
  return { kind = "zones", id = uiMapID, name = okN and type(name) == "string" and name or seams.ZoneName() }
end

-- BlockedHere(info): the place when the player blocked it (a zone also
-- when a map it lies in is blocked), else nil
function Runs.BlockedHere(info)
  local place = Runs.Place(info)
  if not place then return nil end
  local Prefs = CobysLootSweeper.Prefs
  if place.kind == "instances" then return Prefs.IsBlocked("instances", place.id) and place or nil end
  return Prefs.BlockedZone(place.id) and place or nil
end

-- BlockHere(): never track where the player stands; a run here ends, and
-- the loot it found stays listed
function Runs.BlockHere()
  if CobysLootSweeper.Utilities.Guarded("block") then return false end
  local place = Runs.Place()
  if not place then
    seams.Message("Loot Sweeper can't tell where you are right now. Try again in a moment.")
    return false
  end
  CobysLootSweeper.Prefs.Block(place.kind, place.id, place.name)
  Debug().Log("RUN", "Blocked %s %s (%s)", place.kind, tostring(place.id), tostring(place.name))
  if Runs.Char().run or pendingStart then Runs.Stop() end
  seams.Message(string.format("Loot Sweeper won't track %s any more. Loot it already found stays listed; /ls kept undoes it.",
    place.name or "this place"))
  Bus():Fire(Events.RunChanged)
  return true
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
  local changes = WithoutKept(char, Ledger.CloseContainerSession(char.ledger, { runId = run and run.id, now = seams.Time() }))
  if HasChanges(changes) then
    LogChanges(changes)
    CobysLootSweeper.History.OnChanges(changes, char.ledger, seams.Time())
    Bus():Fire(Events.PileChanged)
  end
end

local handlers = {
  -- A loading screen closes the windows a close never came for (Task #109);
  -- here, not in OnEnteringWorld, so suites that call it leave the real
  -- fences alone
  PLAYER_ENTERING_WORLD = function(isLogin, isReload)
    if not (isLogin or isReload) then Fences.OnLoadingScreen() end
    Runs.OnEnteringWorld(isLogin, isReload)
  end,
  BAG_UPDATE_DELAYED = function() Runs.RequestReconcile() end,
  PLAYER_EQUIPMENT_CHANGED = function() Runs.RequestReconcile() end,
  -- The buyback list changed after a sale with no bag change to follow
  MERCHANT_UPDATE = function() Runs.RequestReconcile() end,
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) Fences.OnInteraction(kind, true) end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind)
    Fences.OnInteraction(kind, false)
    Runs.RequestReconcile()
  end,
  QUEST_TURNED_IN = function() Fences.Pulse() end,
  ACTIVE_DELVE_DATA_UPDATE = function() Runs.CheckOffer() end,
  LOOT_OPENED = function(_, isFromItem) Fences.OnLootOpened(isFromItem, Runs.Ledger()) end,
  LOOT_CLOSED = function() Fences.OnLootClosed(OnContainerClosed) end,
  CHAT_MSG_LOOT = function(text) OnLootChat(text) end,
}
for event in pairs(Fences.WINDOW_EVENTS) do
  handlers[event] = function() Fences.OnWindowEvent(event) end
end
Runs._test.handlers = handlers

-- Tests: set the module's own state (resync, pending start)
function Runs._test.SetState(opts)
  vetoes = 0
  expect = nil
  visit.mapID, visit.offered, visit.once = nil, nil, nil
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
           retryScheduled = retryScheduled, vetoes = vetoes, expect = expect,
           visit = { mapID = visit.mapID, offered = visit.offered, once = visit.once } }
end
function Runs._test.Restore(saved)
  resyncPending, pendingStart, preparing = saved.resyncPending, saved.pendingStart, saved.preparing
  retryScheduled, vetoes, expect = saved.retryScheduled, saved.vetoes, saved.expect
  -- The real offer (the same object: its delayed announcement checks it)
  -- and "Yes, this time" come back too (review 2026-10-01, TEST-01)
  local v = saved.visit or {}
  visit.mapID, visit.offered, visit.once = v.mapID, v.offered, v.once
end

-- When a fence's tail runs out, one read settles it
Fences.SetTailCallback(function() Runs.RequestReconcile() end)

local frame = CreateFrame("Frame")
for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler then handler(...) end
end)
