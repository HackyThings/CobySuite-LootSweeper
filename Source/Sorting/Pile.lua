-------------------------------------------------------------------------------
-- Pile: the sorted view of the pile the window, the notices and the seller
-- read
--
-- Rows() returns every pile entry still in the bags, each
--   { guid, entry, bag, slot, facts, quote, bucket, reason, hard, value,
--     vendorValue, ahValue, runName, pref, remembered, group, deletable }
--   group: a Vendor row's quick-sell group (Rules.Group); deletable: a Keep
--   row no vendor buys that the player may delete (Rules.Deletable)
-- Summary(runId) returns { vendor = { count, value }, post = {...}, keep =
--   {...}, current = {...}, groups = { junk = { count, value }, bound,
--   other, tradeable, warbound }, deletable = count, runs = number of runs
--   with items waiting } for the whole pile, or for one run's loot.
--   Bucket(bucket, compare, runId, group) the same way (group: one
--   quick-sell group of the Vendor list).
-- RunList() returns the runs with loot waiting, the active run first, then
--   newest first. Loot with no run (Pile.OTHER) is listed last as its own
--   entry.
-- The rows are rebuilt lazily on the next read after PileChanged,
-- ViewChanged (prices, item data), ConfigChanged or RunChanged, or an item,
-- collection or equipment-set event; ViewUpdated follows, coalesced 0.25 s.
-- Items whose data is still loading are asked for and re-sorted when it
-- arrives.
-------------------------------------------------------------------------------
local Pile = {}
CobysLootSweeper.Pile = Pile

local Events = CobysLootSweeper.Events

local seams = {
  Locate = function(guid) return CobysLootSweeper.Bags.Locate(guid) end,
  RequestItem = function(itemID) C_Item.RequestLoadItemDataByID(itemID) end,
}
Pile._test = { seams = seams }

local rows = nil     -- nil: rebuild on next read
local summaries = {} -- [runId or "all"] = summary
local runList = nil

-- The run key of loot claimed with no run (a container opened later)
Pile.OTHER = 0
-- The quick-sell groups of the Vendor list, in button order
Pile.GROUPS = { "junk", "bound", "other", "tradeable", "warbound" }

local function Invalidate()
  rows, summaries, runList = nil, {}, nil
end

local function RunKey(row) return row.entry.runId or Pile.OTHER end
local function InRun(row, runId) return runId == nil or RunKey(row) == runId end

local function BuildRow(guid, entry, settings)
  local bag, slot, info = seams.Locate(guid)
  if not bag or info.itemID ~= entry.itemID then return nil end
  local facts = CobysLootSweeper.Facts.Read(bag, slot, info)
  if not facts then return nil end
  if not facts.loaded then pcall(seams.RequestItem, entry.itemID) end
  local quote = CobysLootSweeper.Prices.Quote(facts.link)
  local pref, remembered = CobysLootSweeper.Prefs.For(entry)
  local result = CobysLootSweeper.Rules.Classify(entry, facts, quote, pref, settings)
  local Rules = CobysLootSweeper.Rules
  return {
    guid = guid, entry = entry, bag = bag, slot = slot, facts = facts, quote = quote,
    bucket = result.bucket, reason = result.reason, hard = result.hard,
    value = result.value, vendorValue = result.vendorValue, ahValue = result.ahValue,
    runName = CobysLootSweeper.Runs.RunName(entry.runId), pref = pref, remembered = remembered,
    group = result.bucket == Rules.VENDOR and Rules.Group(facts) or nil,
    deletable = result.bucket == Rules.KEEP and Rules.Deletable(entry, facts, pref, settings) or false,
  }
end

local function Build()
  local ledger = CobysLootSweeper.Runs.Ledger()
  local settings = CobysLootSweeper.Rules.Settings()
  local list = {}
  for guid, entry in pairs(ledger.pile) do
    local row = BuildRow(guid, entry, settings)
    if row then list[#list + 1] = row end
  end
  return list
end

-- current: what the active run has added so far (the window's live banner)
local function BuildSummary(list, runId)
  local s = { vendor = { count = 0, value = 0 }, post = { count = 0, value = 0 }, keep = { count = 0, value = 0 },
              current = { count = 0, value = 0 }, deletable = 0, groups = {} }
  for _, key in ipairs(Pile.GROUPS) do s.groups[key] = { count = 0, value = 0 } end
  local runs = {}
  local run = CobysLootSweeper.Runs.Active()
  for _, row in ipairs(list) do
    if InRun(row, runId) then
      local b = s[row.bucket]
      b.count = b.count + 1
      b.value = b.value + (row.value or 0)
      local g = row.group and s.groups[row.group]
      if g then
        g.count = g.count + 1
        g.value = g.value + (row.vendorValue or 0)
      end
      if row.deletable then s.deletable = s.deletable + 1 end
      runs[RunKey(row)] = true
      if run and row.entry.runId == run.id then
        s.current.count = s.current.count + 1
        s.current.value = s.current.value + (row.value or 0)
      end
    end
  end
  s.runs = CobySuite_CobysLootSweeper.Utilities.TableCount(runs)
  return s
end

function Pile.Rows()
  if not rows then
    rows = Build()
    summaries, runList = {}, nil
  end
  return rows
end

-- Summary(runId): the whole pile, or one run's loot
function Pile.Summary(runId)
  local list = Pile.Rows()
  local key = runId or "all"
  if not summaries[key] then summaries[key] = BuildSummary(list, runId) end
  return summaries[key]
end

-- The rows of one bucket, in the order given (default: value, highest first),
-- from the whole pile or one run
function Pile.Bucket(bucket, compare, runId, group)
  local out = {}
  for _, row in ipairs(Pile.Rows()) do
    if row.bucket == bucket and InRun(row, runId) and (group == nil or row.group == group) then out[#out + 1] = row end
  end
  table.sort(out, compare or function(a, b)
    if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
    return (a.facts.name or "") < (b.facts.name or "")
  end)
  return out
end

-- RunList(): { id, name, startedAt, endedAt, active, count, vendorCount,
-- vendorValue, postCount, keepCount } per run with loot waiting, the active
-- run first, then newest first; loot with no run last
function Pile.RunList()
  if runList then return runList end
  local Runs = CobysLootSweeper.Runs
  local active = Runs.Active()
  local byId, list = {}, {}
  for _, row in ipairs(Pile.Rows()) do
    local id = RunKey(row)
    local r = byId[id]
    if not r then
      local info = id ~= Pile.OTHER and Runs.Info(id) or nil
      r = { id = id, name = info and info.name, startedAt = info and info.startedAt, endedAt = info and info.endedAt,
            active = active ~= nil and active.id == id, count = 0, vendorCount = 0, vendorValue = 0,
            postCount = 0, keepCount = 0 }
      byId[id] = r
      list[#list + 1] = r
    end
    r.count = r.count + 1
    if row.bucket == "vendor" then
      r.vendorCount = r.vendorCount + 1
      r.vendorValue = r.vendorValue + (row.vendorValue or 0)
    elseif row.bucket == "post" then
      r.postCount = r.postCount + 1
    else
      r.keepCount = r.keepCount + 1
    end
  end
  table.sort(list, function(a, b)
    if a.active ~= b.active then return a.active end
    if (a.id == Pile.OTHER) ~= (b.id == Pile.OTHER) then return b.id == Pile.OTHER end
    return (a.startedAt or 0) > (b.startedAt or 0)
  end)
  runList = list
  return list
end

-- Keep rows no vendor buys that the player may delete, by name
function Pile.Deletable(runId)
  local out = {}
  for _, row in ipairs(Pile.Rows()) do
    if row.deletable and InRun(row, runId) then out[#out + 1] = row end
  end
  table.sort(out, function(a, b) return (a.facts.name or "") < (b.facts.name or "") end)
  return out
end

function Pile.Invalidate()
  Invalidate()
  CobysLootSweeper.EventBus:Fire(Events.ViewUpdated)
end

-------------------------------------------------------------------------------
-- Listeners: anything that can change a row's sort marks the view stale
-------------------------------------------------------------------------------
local notify = CobySuite_CobysLootSweeper.Utilities.Coalesce(0.25, function()
  CobysLootSweeper.EventBus:Fire(Events.ViewUpdated)
end)

local listener = {}
function listener:ReceiveEvent()
  Invalidate()
  notify:Call()
end
CobysLootSweeper.EventBus:Register(listener, { Events.PileChanged, Events.ViewChanged, Events.ConfigChanged, Events.RunChanged })

local refreshEvents = {
  "GET_ITEM_INFO_RECEIVED", "TRANSMOG_COLLECTION_UPDATED", "NEW_MOUNT_ADDED",
  "NEW_PET_ADDED", "NEW_TOY_ADDED", "EQUIPMENT_SETS_CHANGED",
}
local frame = CreateFrame("Frame")
for _, event in ipairs(refreshEvents) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function()
  if rows == nil then return end   -- nothing built yet, nothing stale
  Invalidate()
  notify:Call()
end)
