-------------------------------------------------------------------------------
-- Signals: what the game says about where loot came from (diagnostics only)
--
-- Records the events a later build may use as receipts for quest, world
-- quest, delve and open-world loot, and claims nothing: which ones fire, in what order against the bag change,
-- and whether their values are readable or secret in 12.x. Kept in the
-- character's diag table (Check Sweep reports it):
--   diag.signals = {
--     counts = { [event] = { seen, secret } },
--     trace  = { { e, t, f, bagBefore, bagAfter }, ... }   the last TRACE_MAX
--     delve  = { why, at, active, lair, type, difficulty, mapID }   the last delve check
--   }
--   f          the payload's readable fields ("secret" for a secret one)
--   bagBefore  seconds since the last bag change, when one came within BAG_WINDOW
--   bagAfter   seconds until the next bag change, filled in when it comes
-- Every client call goes through Signals._test.seams.
-------------------------------------------------------------------------------
local Signals = {}
CobysLootSweeper.Signals = Signals

local Utilities = CobysLootSweeper.Utilities
local Try = Utilities.Try

Signals.TRACE_MAX = 60
Signals.BAG_WINDOW = 3   -- seconds either side of an event that a bag change counts as near it

local seams = {
  Now = function() return GetTime() end,
  Stamp = function() return time() end,
  IsSecret = function(value) return Utilities.IsSecret(value) end,
  PlayerName = function() return (UnitName("player")) end,
  NumLootItems = function() return GetNumLootItems() end,
  LootSlotLink = function(slot) return GetLootSlotLink(slot) end,
  HasActiveDelve = function() return C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve() end,
  IsInLair = function() return C_DelvesUI and C_DelvesUI.IsInLair and C_DelvesUI.IsInLair() end,
  InstanceInfo = function() return GetInstanceInfo() end,
  IsWorldQuest = function(questID) return C_QuestLog.IsWorldQuest(questID) end,
}
Signals._test = { seams = seams }

local lastBagAt = nil

local function Diag()
  local diag = CobysLootSweeper.Runs.Char().diag
  if type(diag.signals) ~= "table" then diag.signals = {} end
  local s = diag.signals
  if type(s.counts) ~= "table" then s.counts = {} end
  if type(s.trace) ~= "table" then s.trace = {} end
  return s
end

-- A value as the report shows it: "secret" for a secret one, a short string
-- for text, the value itself otherwise
local function Show(value)
  if seams.IsSecret(value) then return "secret" end
  if type(value) == "string" then return (value:gsub("|", "||"):sub(1, 80)) end
  return value
end

-- Summarize(event, ...) -> fields, anySecret: the payload values a report
-- can show
function Signals.Summarize(event, ...)
  local fields, secret = {}, false
  local function Put(name, value)
    local shown = Show(value)
    if shown == "secret" then secret = true end
    fields[name] = shown
  end
  if event == "QUEST_LOOT_RECEIVED" then
    local questID, link, quantity = ...
    Put("questID", questID)
    Put("link", link)
    Put("quantity", quantity)
    if type(questID) == "number" and not seams.IsSecret(questID) then
      local ok, wq = Try(seams.IsWorldQuest, questID)
      fields.worldQuest = ok and Show(wq) or "unreadable"
    end
  elseif event == "QUEST_TURNED_IN" then
    local questID = ...
    Put("questID", questID)
  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, itemID, link, quantity, fifth = ...
    Put("encounterID", encounterID)
    Put("itemID", itemID)
    Put("link", link)
    Put("quantity", quantity)
    -- Blizzard's boss banner reads the fifth value as the receiver's name
    if seams.IsSecret(fifth) then
      fields.receiver = "secret"
      secret = true
    else
      local ok, me = Try(seams.PlayerName)
      fields.receiver = (ok and type(fifth) == "string" and fifth == me) and "me" or (fifth ~= nil and "other" or "none")
    end
  elseif event == "SHOW_LOOT_TOAST" then
    local kind, link, quantity, _, _, personal, method = ...
    Put("kind", kind)
    Put("link", link)
    Put("quantity", quantity)
    Put("personal", personal)
    Put("method", method)
  elseif event == "LOOT_READY" then
    local okN, n = Try(seams.NumLootItems)
    local readable, hidden = 0, 0
    if okN and type(n) == "number" and not seams.IsSecret(n) then
      for slot = 1, n do
        local ok, link = Try(seams.LootSlotLink, slot)
        if ok and seams.IsSecret(link) then hidden = hidden + 1 else readable = readable + 1 end
      end
      fields.slots = n
    else
      fields.slots = "unreadable"
    end
    fields.readableLinks, fields.secretLinks = readable, hidden
    if hidden > 0 then secret = true end
  end
  return fields, secret
end

-- Record(s, event, fields, secret, now): adds a trace line and counts it
function Signals.Record(s, event, fields, secret, now)
  local c = s.counts[event]
  if type(c) ~= "table" then
    c = { seen = 0, secret = 0 }
    s.counts[event] = c
  end
  c.seen = c.seen + 1
  if secret then c.secret = c.secret + 1 end
  local line = { e = event, t = now, f = fields }
  if lastBagAt and now - lastBagAt <= Signals.BAG_WINDOW then
    line.bagBefore = math.floor((now - lastBagAt) * 100 + 0.5) / 100
  end
  s.trace[#s.trace + 1] = line
  while #s.trace > Signals.TRACE_MAX do table.remove(s.trace, 1) end
  return line
end

-- A bag change: the lines waiting for one learn how long after them it came
function Signals.OnBagChange(s, now)
  lastBagAt = now
  for i = #s.trace, 1, -1 do
    local line = s.trace[i]
    if type(line.t) ~= "number" or now - line.t > Signals.BAG_WINDOW then break end
    if line.bagAfter == nil then
      line.bagAfter = math.floor((now - line.t) * 100 + 0.5) / 100
    end
  end
end

-- Where a delve stands now (the game's own difficulty display reads the
-- same two answers)
function Signals.CheckDelve(s, why)
  local okA, active = Try(seams.HasActiveDelve)
  local okL, lair = Try(seams.IsInLair)
  local ok, _, instanceType, difficulty, _, _, _, _, mapID = Try(seams.InstanceInfo)
  s.delve = {
    why = why, at = seams.Stamp(),
    active = okA and Show(active) or "unreadable", lair = okL and Show(lair) or "unreadable",
    type = ok and Show(instanceType) or "unreadable", difficulty = ok and Show(difficulty) or nil,
    mapID = ok and Show(mapID) or nil,
  }
  return s.delve
end

function Signals.Reset(s)
  s.counts, s.trace, s.delve = {}, {}, nil
  lastBagAt = nil
end

local TRACKED = {
  QUEST_LOOT_RECEIVED = true, QUEST_TURNED_IN = true, ENCOUNTER_LOOT_RECEIVED = true,
  SHOW_LOOT_TOAST = true, LOOT_READY = true,
}
local DELVE = { PLAYER_ENTERING_WORLD = true, ACTIVE_DELVE_DATA_UPDATE = true, WALK_IN_DATA_UPDATE = true }
Signals.TRACKED, Signals.DELVE = TRACKED, DELVE

local function OnEvent(event, ...)
  local s = Diag()
  local now = seams.Now()
  if event == "BAG_UPDATE_DELAYED" then
    Signals.OnBagChange(s, now)
  elseif TRACKED[event] then
    local fields, secret = Signals.Summarize(event, ...)
    Signals.Record(s, event, fields, secret, now)
    CobysLootSweeper.Debug.Log("TRACK", "Signal %s%s", event, secret and " (secret values)" or "")
  elseif DELVE[event] then
    local d = Signals.CheckDelve(s, event)
    if d.active == true or d.lair == true then
      CobysLootSweeper.Debug.Log("TRACK", "Delve check (%s): active=%s lair=%s type=%s",
        event, tostring(d.active), tostring(d.lair), tostring(d.type))
    end
  end
end
Signals._test.OnEvent = OnEvent

local frame = CreateFrame("Frame")
for event in pairs(TRACKED) do frame:RegisterEvent(event) end
for event in pairs(DELVE) do pcall(frame.RegisterEvent, frame, event) end
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event, ...) OnEvent(event, ...) end)
