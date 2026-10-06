-------------------------------------------------------------------------------
-- Instance: is this a dungeon or raid from a past expansion? (design section 6)
--
-- Evaluate() returns
--   { eligible, name, instanceType, instanceMapID, journalID, expansion, difficultyID, reason }
-- eligible is true only for a party or raid instance on the shipped list
-- (Data.Instances) whose expansion is older than the server's, and none of
-- the exclusions: Mythic+ (difficulty 8, or a challenge running),
-- Timewalking (24 and 33), a Remix character, or a dungeon in the current
-- Mythic+ season's pool (its seasonal versions scale to current content).
-- Nothing here selects anything in the Encounter Journal. Every client call
-- goes through Instance._test.seams.
-------------------------------------------------------------------------------
local Instance = {}
CobysLootSweeper.Instance = Instance

local Try = CobysLootSweeper.Utilities.Try

local EXCLUDED_DIFFICULTY = {
  [8] = "a Mythic+ keystone run",
  [24] = "Timewalking",
  [33] = "Timewalking",
}

local seams = {
  GetInstanceInfo = function() return GetInstanceInfo() end,
  GetInstanceForGameMap = function(mapID) return C_EncounterJournal.GetInstanceForGameMap(mapID) end,
  GetServerExpansionLevel = function() return GetServerExpansionLevel() end,
  TimerunningSeasonID = function()
    return PlayerGetTimerunningSeasonID and PlayerGetTimerunningSeasonID() or nil
  end,
  IsChallengeModeActive = function()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
  end,
  HasActiveDelve = function() return C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve() end,
  SeasonMapIDs = function()
    local ids = {}
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return ids end
    for _, challengeID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
      local mapID = select(6, C_ChallengeMode.GetMapUIInfo(challengeID))
      if mapID then ids[mapID] = true end
    end
    return ids
  end,
}
Instance._test = { seams = seams }

local function Result(eligible, reason, info)
  info = info or {}
  info.eligible = eligible
  info.reason = reason
  return info
end

-- The expansion the instance came out in, or nil when it isn't on the list
function Instance.ExpansionOf(instanceMapID)
  local data = CobysLootSweeper.Data
  if not data or type(instanceMapID) ~= "number" then return nil end
  local ok, journalID = Try(seams.GetInstanceForGameMap, instanceMapID)
  if ok and type(journalID) == "number" and data.Journal[journalID] then
    return data.Journal[journalID], journalID
  end
  return data.Saved[instanceMapID], (ok and journalID or nil)
end

local function Exclusion(info)
  local byDifficulty = EXCLUDED_DIFFICULTY[info.difficultyID]
  if byDifficulty then return byDifficulty end
  local okC, challenge = Try(seams.IsChallengeModeActive)
  if okC and challenge == true then return "a Mythic+ keystone run" end
  local okT, season = Try(seams.TimerunningSeasonID)
  if okT and type(season) == "number" and season > 0 then return "a Remix character" end
  local okS, pool = Try(seams.SeasonMapIDs)
  if okS and type(pool) == "table" and pool[info.instanceMapID] then
    return "this season's Mythic+ dungeons"
  end
  return nil
end

-- A Mythic+ keystone run (difficulty 8, or a challenge running)
function Instance.IsKeystone(info)
  if info.difficultyID == 8 then return true end
  local ok, challenge = Try(seams.IsChallengeModeActive)
  return ok and challenge == true
end

-- Offerable(info): current content Loot Sweeper offers to track (it never
-- starts by itself there): a dungeon or raid
-- from this expansion, or not on the old-content list, or an old dungeon in
-- this season's Mythic+ pool outside a keystone; or a delve or lair.
-- Never a keystone run, Timewalking or a Remix character
function Instance.Offerable(info)
  if info.eligible or type(info.instanceMapID) ~= "number" or Instance.IsKeystone(info) then return false end
  if EXCLUDED_DIFFICULTY[info.difficultyID] then return false end
  local okT, season = Try(seams.TimerunningSeasonID)
  if okT and type(season) == "number" and season > 0 then return false end
  local t = info.instanceType
  if t == "party" or t == "raid" then
    return info.expansion == nil or info.reason == "current content" or info.reason == "this season's Mythic+ dungeons"
  end
  -- A delve is an instance (a scenario); outdoors a delve answer is stale
  if t == nil or t == "none" then return false end
  local ok, delve = Try(seams.HasActiveDelve)
  return ok and delve == true
end

function Instance.Evaluate()
  local ok, name, instanceType, difficultyID, _, _, _, _, instanceMapID = Try(seams.GetInstanceInfo)
  if not ok then return Result(false, "the instance could not be read") end
  local info = { name = name, instanceType = instanceType, difficultyID = difficultyID, instanceMapID = instanceMapID }
  if instanceType ~= "party" and instanceType ~= "raid" then
    return Result(false, "not in a dungeon or raid", info)
  end
  local expansion, journalID = Instance.ExpansionOf(instanceMapID)
  info.expansion, info.journalID = expansion, journalID
  if expansion == nil then return Result(false, "not on the list of old dungeons and raids", info) end
  local okE, current = Try(seams.GetServerExpansionLevel)
  if not okE or type(current) ~= "number" then return Result(false, "the current expansion could not be read", info) end
  if expansion >= current then return Result(false, "current content", info) end
  local excluded = Exclusion(info)
  if excluded then return Result(false, excluded, info) end
  return Result(true, nil, info)
end
