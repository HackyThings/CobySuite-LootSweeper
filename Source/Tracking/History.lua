-------------------------------------------------------------------------------
-- History: every item a run looted and what became of it (per character)
--
-- COBYS_LOOT_SWEEPER_CHAR.history = {
--   records = { { guid, itemID, link, runId, run, at, count, fromToken,
--                 outcome, copper, doneAt }, ... }   oldest first, at most History.MAX
--   totals  = { looted, sold, copper, deleted }   all time, never trimmed
--   runs    = { [runId] = { name, startedAt, endedAt, looted, sold, copper } }
-- }
-- outcome: nil while the item still waits, "sold", "deleted", "equipped",
-- "left" (banked, mailed, traded or sold elsewhere), "let go" (Forget),
-- "used" (a token used from Loot Sweeper; what it gave has its own record) or
-- "combined" (merged into another stack, which carries the claim). A split's
-- new stack gets its own record, not counted as new loot, so its sale is
-- the run's (HIST-01).
-- Records follow the ledger's changes (Runs passes them in), the seller's
-- confirmed sales and the delete panel. Clear() empties everything.
-------------------------------------------------------------------------------
local History = {}
CobysLootSweeper.History = History

History.MAX = 3000
History.TRIM = 200

local LOOTED_WHY = { loot = true, container = true, token = true }

local openFor, open = nil, nil   -- the history table the index was built for, guid -> record

local function Fire() CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.HistoryChanged) end

local function Number(t, key)
  if type(t[key]) ~= "number" then t[key] = 0 end
end

-- The history table, repaired: what every call reads and writes
function History.Data()
  local char = CobysLootSweeper.Runs.Char()
  local h = char.history
  if type(h) ~= "table" then
    h = {}
    char.history = h
  end
  if type(h.records) ~= "table" then h.records = {} end
  if type(h.totals) ~= "table" then h.totals = {} end
  for _, key in ipairs({ "looted", "sold", "copper", "deleted" }) do Number(h.totals, key) end
  if type(h.runs) ~= "table" then h.runs = {} end
  return h
end

-- guid -> the record still waiting for an outcome
local function Open(h)
  if openFor ~= h then
    open = {}
    for _, rec in ipairs(h.records) do
      if type(rec) == "table" and rec.outcome == nil and type(rec.guid) == "string" then open[rec.guid] = rec end
    end
    openFor = h
  end
  return open
end

local function RunStats(h, runId)
  if type(runId) ~= "number" then return nil end
  local r = h.runs[runId]
  if type(r) ~= "table" then
    local info = CobysLootSweeper.Runs.Info(runId) or {}
    r = { name = info.name, startedAt = info.startedAt, endedAt = info.endedAt }
    h.runs[runId] = r
  end
  for _, key in ipairs({ "looted", "sold", "copper" }) do Number(r, key) end
  return r
end

local function Trim(h)
  if #h.records <= History.MAX then return end
  local keep = {}
  local drop = #h.records - History.MAX + History.TRIM
  for i = drop + 1, #h.records do keep[#keep + 1] = h.records[i] end
  h.records = keep
  openFor = nil
end

local function Close(guid, outcome, copper, now)
  local h = History.Data()
  local rec = Open(h)[guid]
  if not rec then return nil, h end
  rec.outcome = outcome
  rec.copper = copper
  rec.doneAt = now or time()
  open[guid] = nil
  return rec, h
end

-- A run's loot joined the pile. moved: a split's new stack, recorded but
-- not counted as new loot
function History.Looted(guid, entry, now, moved)
  local h = History.Data()
  local index = Open(h)
  if index[guid] or type(entry) ~= "table" then return end
  local rec = {
    guid = guid, itemID = entry.itemID, link = entry.link, runId = entry.runId,
    run = CobysLootSweeper.Runs.RunName(entry.runId), at = now or time(),
    count = (entry.count or 0) + (entry.added or 0),
    fromToken = entry.fromToken == true or nil,   -- a rescue keeps the token rule
  }
  h.records[#h.records + 1] = rec
  index[guid] = rec
  if not moved then
    h.totals.looted = h.totals.looted + 1
    local r = RunStats(h, entry.runId)
    if r then r.looted = r.looted + 1 end
  end
  Trim(h)
end

-- Loot Sweeper sold it for copper
function History.Sold(guid, copper)
  local rec, h = Close(guid, "sold", copper)
  h.totals.sold = h.totals.sold + 1
  h.totals.copper = h.totals.copper + (copper or 0)
  local r = rec and RunStats(h, rec.runId)
  if r then
    r.sold = r.sold + 1
    r.copper = r.copper + (copper or 0)
  end
  Fire()
end

-- A token used from Loot Sweeper (what it gave is recorded as loot)
function History.Used(guid, now)
  Close(guid, "used", nil, now)
  Fire()
end

-- The delete panel deleted it
function History.Deleted(guid)
  local _, h = Close(guid, "deleted")
  h.totals.deleted = h.totals.deleted + 1
  Fire()
end

-- The ledger's changes from one read (Runs.Reconcile, container sessions)
function History.OnChanges(changes, ledger, now)
  local any = false
  for _, c in ipairs(changes.claimed or {}) do
    if LOOTED_WHY[c.why] and ledger.pile[c.guid] then
      History.Looted(c.guid, ledger.pile[c.guid], now)
      any = true
    elseif (c.why == "moved" or c.why == "merged") and ledger.pile[c.guid] then
      History.Looted(c.guid, ledger.pile[c.guid], now, true)
      any = true
    end
  end
  for _, c in ipairs(changes.held or {}) do
    -- New loot that landed in a mixed stack is still loot the run found
    if ledger.pile[c.guid] and not Open(History.Data())[c.guid] and c.why == "mixed" then
      History.Looted(c.guid, ledger.pile[c.guid], now)
      any = true
    end
  end
  for _, c in ipairs(changes.released or {}) do
    if c.why == "equipped" then
      any = Close(c.guid, "equipped", nil, now) ~= nil or any
    elseif c.why == "gone" then
      any = Close(c.guid, "left", nil, now) ~= nil or any
    elseif c.why == "moved" then
      any = Close(c.guid, "combined", nil, now) ~= nil or any
    end
  end
  if any then Fire() end
end

-- Forget: the pile let go of these items (runId, or every run)
function History.LetGo(runId, now)
  local h = History.Data()
  local index = Open(h)
  for guid, rec in pairs(index) do
    if runId == nil or (rec.runId or 0) == runId then
      rec.outcome = "let go"
      rec.doneAt = now or time()
      index[guid] = nil
    end
  end
  Fire()
end

function History.RunEnded(runId, endedAt)
  local r = RunStats(History.Data(), runId)
  if r then r.endedAt = endedAt end
end

-- Records, newest first, matching an optional run and search text
function History.Records(runId, search)
  local h = History.Data()
  local needle = search and search ~= "" and search:lower() or nil
  local out = {}
  for i = #h.records, 1, -1 do
    local rec = h.records[i]
    if type(rec) == "table" and (runId == nil or (rec.runId or 0) == runId) then
      local name = rec.link and rec.link:match("%[(.-)%]") or ""
      if not needle or name:lower():find(needle, 1, true) or (rec.run or ""):lower():find(needle, 1, true) then
        out[#out + 1] = rec
      end
    end
  end
  return out
end

-- Totals for all time, or for one run
function History.Totals(runId)
  local h = History.Data()
  if runId == nil then return h.totals end
  return RunStats(h, runId) or { looted = 0, sold = 0, copper = 0 }
end

-- RunList(): { id, name, startedAt, endedAt, count = looted, sold, copper,
-- history = true } per run with anything recorded, newest first (the run
-- picker on the History tab, finished runs included)
function History.RunList()
  local h = History.Data()
  local active = CobysLootSweeper.Runs.Active()
  local list = {}
  for id, r in pairs(h.runs) do
    if type(id) == "number" and type(r) == "table" and (r.looted or 0) > 0 then
      list[#list + 1] = { id = id, name = r.name, startedAt = r.startedAt, endedAt = r.endedAt,
        active = active ~= nil and active.id == id, count = r.looted or 0, sold = r.sold or 0,
        copper = r.copper or 0, history = true }
    end
  end
  table.sort(list, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
  return list
end

-- The records still waiting for an outcome (never sold, deleted, banked):
-- what Runs.RescueFromHistory offers Ledger.Rescue after a login or /reload
function History.OpenRecords()
  local out = {}
  for _, rec in pairs(Open(History.Data())) do out[#out + 1] = rec end
  return out
end

-- A run the history knows, for a rescue that brings its loot back
function History.RunInfo(runId)
  local r = type(runId) == "number" and History.Data().runs[runId]
  return type(r) == "table" and r or nil
end

-- True when anything is recorded (Clear history has something to clear)
function History.HasAny()
  local h = History.Data()
  return #h.records > 0 or h.totals.looted > 0 or h.totals.copper > 0 or h.totals.deleted > 0
end

function History.Clear()
  local char = CobysLootSweeper.Runs.Char()
  char.history = nil
  openFor = nil
  History.Data()
  Fire()
end
