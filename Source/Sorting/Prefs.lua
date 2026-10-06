-------------------------------------------------------------------------------
-- Prefs: the player's lists: kept items, remembered Sells and blocked places
--
-- Keep (the menu's Keep): every copy of the item ID is let go now and never
-- claimed again; Loot Sweeper doesn't list it any more. Sell: a copy's own
-- choice (entry.pref = "sell", gone with the entry), or remembered for the
-- item ID ("Remember Sell for future copies"). Blocked: instances (instance map
-- ID), zones (uiMapID; a blocked zone blocks the maps inside it), delves and
-- quests (kept for later builds) are never tracked.
--
-- Everything lives in the account-wide COBYS_LOOT_SWEEPER_PREFS, so another
-- character's lists can be imported:
--   mode    "character" (default) or "account"
--   chars   [charKey] = Lists, one per character the addon has seen
--   account Lists, used by every character while mode is "account"
--   seed    Lists a character seen for the first time starts with, set when
--           the lists go back to per character (empty or a copy of the
--           account lists); nil before any switch
--   items   the account-wide remembered choices of 0.0.1 ([itemID] = "keep"
--           or "sell"): frozen, read only to start a character seen for the
--           first time (while seed is nil), never written
-- Lists = { keep = { [itemID] = label }, sell = { [itemID] = label },
--           blocked = { instances = {}, zones = {}, delves = {}, quests = {} },
--           allowed = { [instanceMapID] = label }   current content the
--           player said to track always (Runs' offer, "Yes, always here"),
--           name = "Name - Realm" }; a label is a link or name to show (or
--           true), never a key.
-- Every client call goes through Prefs._test.seams.
-------------------------------------------------------------------------------
local Prefs = {}
CobysLootSweeper.Prefs = Prefs

local Utilities = CobysLootSweeper.Utilities
local Try = Utilities.Try

Prefs.KEEP = "keep"
Prefs.SELL = "sell"
Prefs.BLOCK_KINDS = { "instances", "zones", "delves", "quests" }
Prefs.MAX_PARENTS = 12   -- map levels a zone block looks up through

local seams = {
  PlayerName = function() return (UnitName("player")) end,
  -- The normalized name can be missing before login; the realm's own name
  -- without spaces or hyphens is the same text
  RealmName = function()
    local realm = GetNormalizedRealmName()
    if realm then return realm end
    realm = GetRealmName()
    return realm and (realm:gsub("[%s%-]", "")) or nil
  end,
  MapInfo = function(uiMapID) return C_Map.GetMapInfo(uiMapID) end,
}
Prefs._test = { seams = seams }

-------------------------------------------------------------------------------
-- Lists
-------------------------------------------------------------------------------
local function IDMap(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for id, label in pairs(t) do
    if type(id) == "number" and label ~= nil and label ~= false then
      out[id] = (type(label) == "string" or label == true) and label or true
    end
  end
  return out
end

-- A list table repaired, or a new empty one
function Prefs.NormalizeLists(lists)
  if type(lists) ~= "table" then lists = {} end
  lists.keep = IDMap(lists.keep)
  lists.sell = IDMap(lists.sell)
  lists.allowed = IDMap(lists.allowed)
  local blocked = type(lists.blocked) == "table" and lists.blocked or {}
  for _, kind in ipairs(Prefs.BLOCK_KINDS) do blocked[kind] = IDMap(blocked[kind]) end
  lists.blocked = blocked
  if type(lists.name) ~= "string" then lists.name = nil end
  return lists
end

local function Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Copy(v) end
  return out
end

function Prefs.CopyLists(lists, name)
  local src = Prefs.NormalizeLists(Copy(lists))
  src.name = name or src.name
  return src
end

local function Count(t) return CobySuite_CobysLootSweeper.Utilities.TableCount(t) end

function Prefs.CountLists(lists)
  local blocked = 0
  for _, kind in ipairs(Prefs.BLOCK_KINDS) do blocked = blocked + Count(lists.blocked[kind]) end
  return { keep = Count(lists.keep), sell = Count(lists.sell), blocked = blocked }
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------
function Prefs.CharKey()
  local okN, name = Try(seams.PlayerName)
  local okR, realm = Try(seams.RealmName)
  if not okN or type(name) ~= "string" or Utilities.IsSecret(name) or name == "" then return nil end
  if not okR or type(realm) ~= "string" or Utilities.IsSecret(realm) or realm == "" then return nil end
  return name .. "-" .. realm, name .. " - " .. realm
end

-- A character seen for the first time: the seed after a switch, else the
-- 0.0.1 remembered choices
local function FirstLists(sv, display)
  if sv.seed then return Prefs.CopyLists(sv.seed, display) end
  local lists = Prefs.NormalizeLists(nil)
  for itemID, value in pairs(sv.items) do
    if value == Prefs.KEEP then lists.keep[itemID] = true end
    if value == Prefs.SELL then lists.sell[itemID] = true end
  end
  lists.name = display
  return lists
end

function Prefs.InitializeData()
  local sv = COBYS_LOOT_SWEEPER_PREFS
  if type(sv) ~= "table" then sv = {} end
  if type(sv.items) ~= "table" then sv.items = {} end
  for itemID, value in pairs(sv.items) do
    if type(itemID) ~= "number" or (value ~= Prefs.KEEP and value ~= Prefs.SELL) then sv.items[itemID] = nil end
  end
  if sv.mode ~= "account" then sv.mode = "character" end
  if type(sv.chars) ~= "table" then sv.chars = {} end
  for key, lists in pairs(sv.chars) do
    if type(key) ~= "string" then sv.chars[key] = nil else sv.chars[key] = Prefs.NormalizeLists(lists) end
  end
  if sv.seed ~= nil then sv.seed = Prefs.NormalizeLists(sv.seed) end
  sv.account = sv.mode == "account" and Prefs.NormalizeLists(sv.account) or nil
  COBYS_LOOT_SWEEPER_PREFS = sv
  local key, display = Prefs.CharKey()
  if key then
    if not sv.chars[key] then sv.chars[key] = FirstLists(sv, display) end
    sv.chars[key].name = display
  end
end

local function SV()
  if type(COBYS_LOOT_SWEEPER_PREFS) ~= "table" or type(COBYS_LOOT_SWEEPER_PREFS.chars) ~= "table" then
    Prefs.InitializeData()
  end
  return COBYS_LOOT_SWEEPER_PREFS
end

local spare = nil   -- lists for a character whose name can't be read yet
-- The lists in use: the account's in account mode, else this character's
function Prefs.Lists()
  local sv = SV()
  if sv.mode == "account" then
    sv.account = sv.account or Prefs.NormalizeLists(nil)
    return sv.account
  end
  local key, display = Prefs.CharKey()
  if not key then
    spare = spare or Prefs.NormalizeLists(nil)
    return spare
  end
  if not sv.chars[key] then sv.chars[key] = FirstLists(sv, display) end
  return sv.chars[key]
end

function Prefs.IsAccountWide() return SV().mode == "account" end

-- Other characters with lists: { { key, name, counts } }, by name
function Prefs.OtherCharacters()
  local me = Prefs.CharKey()
  local out = {}
  for key, lists in pairs(SV().chars) do
    if key ~= me then out[#out + 1] = { key = key, name = lists.name or key, counts = Prefs.CountLists(lists) } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-------------------------------------------------------------------------------
-- Choices
-------------------------------------------------------------------------------
local function Changed() CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.PileChanged) end

function Prefs.IsKept(itemID) return itemID ~= nil and Prefs.Lists().keep[itemID] ~= nil end

-- The choice for this entry, and whether it is remembered for the item:
-- "sell" or nil (a kept item is never in the pile)
function Prefs.For(entry)
  if not entry then return nil end
  if entry.pref == Prefs.SELL then return Prefs.SELL, false end
  if Prefs.Lists().sell[entry.itemID] ~= nil then return Prefs.SELL, true end
  return nil
end

-- Keep(itemID, label): kept for good; its copies are let go now
function Prefs.Keep(itemID, label)
  if type(itemID) ~= "number" or CobysLootSweeper.Utilities.Guarded("keep") then return end
  local lists = Prefs.Lists()
  lists.keep[itemID] = label or true
  lists.sell[itemID] = nil
  CobysLootSweeper.Runs.LetGoKept()
  Changed()
end

-- Set(entry, value, remember): value "keep", "sell" or nil (Automatic)
function Prefs.Set(entry, value, remember)
  if not entry or CobysLootSweeper.Utilities.Guarded("choice") then return end
  if value == Prefs.KEEP then return Prefs.Keep(entry.itemID, entry.link) end
  if value ~= nil and value ~= Prefs.SELL then return end
  local lists = Prefs.Lists()
  if value == nil then
    entry.pref = nil
    lists.sell[entry.itemID] = nil
  elseif remember then
    entry.pref = nil
    lists.sell[entry.itemID] = entry.link or true
  else
    entry.pref = value
  end
  Changed()
end

-------------------------------------------------------------------------------
-- Blocked places
-------------------------------------------------------------------------------
function Prefs.Block(kind, id, label)
  local lists = Prefs.Lists()
  local list = lists.blocked[kind]
  if not list or type(id) ~= "number" then return false end
  list[id] = label or true
  if kind == "instances" then lists.allowed[id] = nil end
  return true
end

-- Current content tracked whenever the player enters it ("Yes, always here")
function Prefs.Allow(instanceMapID, label)
  if type(instanceMapID) ~= "number" then return false end
  Prefs.Lists().allowed[instanceMapID] = label or true
  return true
end

function Prefs.IsAllowed(instanceMapID)
  return instanceMapID ~= nil and Prefs.Lists().allowed[instanceMapID] ~= nil
end

function Prefs.IsBlocked(kind, id)
  local list = Prefs.Lists().blocked[kind]
  return list ~= nil and id ~= nil and list[id] ~= nil
end

-- A zone is blocked when it, or a map it lies in, is blocked: the blocked
-- map's ID, or nil
function Prefs.BlockedZone(uiMapID)
  local zones = Prefs.Lists().blocked.zones
  local id = uiMapID
  for _ = 1, Prefs.MAX_PARENTS do
    if type(id) ~= "number" or id <= 0 then return nil end
    if zones[id] ~= nil then return id end
    local ok, info = Try(seams.MapInfo, id)
    if not ok or type(info) ~= "table" or Utilities.IsSecretTable(info) then return nil end
    id = info.parentMapID
  end
  return nil
end

-------------------------------------------------------------------------------
-- Edits from the settings window (staged there, applied here)
-------------------------------------------------------------------------------
-- An edit list is text, one edit per line, so the settings window can stage
-- it as a value: "remove<TAB>keep<TAB>12345", "remove<TAB>zones<TAB>2248",
-- "import<TAB>Name-Realm"
function Prefs.AddEdit(edits, ...)
  local line = table.concat({ ... }, "\t")
  if edits == nil or edits == "" then return line end
  return edits .. "\n" .. line
end

function Prefs.ParseEdits(edits)
  local out = {}
  for line in tostring(edits or ""):gmatch("[^\n]+") do
    local op, a, b = line:match("^([^\t]+)\t?([^\t]*)\t?([^\t]*)$")
    if op == "remove" then
      out[#out + 1] = { op = op, list = a, id = tonumber(b) }
    elseif op == "import" then
      out[#out + 1] = { op = op, from = a }
    end
  end
  return out
end

-- What importing another character's lists would add here (counts of
-- entries not already in this character's lists)
function Prefs.ImportCounts(fromKey, into)
  local from = SV().chars[fromKey]
  into = into or Prefs.Lists()
  local counts = { keep = 0, sell = 0, blocked = 0 }
  if not from then return counts end
  for id in pairs(from.keep) do if into.keep[id] == nil then counts.keep = counts.keep + 1 end end
  for id in pairs(from.sell) do
    if into.sell[id] == nil and into.keep[id] == nil and from.keep[id] == nil then counts.sell = counts.sell + 1 end
  end
  for _, kind in ipairs(Prefs.BLOCK_KINDS) do
    for id in pairs(from.blocked[kind]) do
      if into.blocked[kind][id] == nil then counts.blocked = counts.blocked + 1 end
    end
  end
  return counts
end

-- Import adds the other character's entries to these lists; nothing here is
-- removed, and a Keep on either side wins over a Sell
local function Import(into, fromKey)
  local from = SV().chars[fromKey]
  if not from or from == into then return false end
  for id, label in pairs(from.keep) do
    into.keep[id] = into.keep[id] or label
    into.sell[id] = nil
  end
  for id, label in pairs(from.sell) do
    if into.keep[id] == nil then into.sell[id] = into.sell[id] or label end
  end
  for _, kind in ipairs(Prefs.BLOCK_KINDS) do
    for id, label in pairs(from.blocked[kind]) do into.blocked[kind][id] = into.blocked[kind][id] or label end
  end
  return true
end

-- ApplyEdits(text): the window's Apply; returns true (false while a scene shows)
function Prefs.ApplyEdits(text)
  if CobysLootSweeper.Utilities.Guarded("list edits") then return false end
  local lists = Prefs.Lists()
  local keptAny, removed = false, 0
  for _, e in ipairs(Prefs.ParseEdits(text)) do
    if e.op == "remove" and e.id then
      removed = removed + 1
      if e.list == "keep" or e.list == "sell" or e.list == "allowed" then
        lists[e.list][e.id] = nil
      elseif lists.blocked[e.list] then
        lists.blocked[e.list][e.id] = nil
      end
    elseif e.op == "import" then
      keptAny = Import(lists, e.from) or keptAny
    end
  end
  if keptAny then CobysLootSweeper.Runs.LetGoKept() end
  -- What the last Apply removed, for Verify's ls.post.lists-applied
  Prefs._test.lastApplied = { removed = removed, at = time() }
  Changed()
  return true
end

-------------------------------------------------------------------------------
-- Per character or account-wide
-------------------------------------------------------------------------------
-- UseAccountWide(fromKey): every character uses one copy of fromKey's lists
-- (default this character's). Characters not seen yet use them too.
function Prefs.UseAccountWide(fromKey)
  if CobysLootSweeper.Utilities.Guarded("share lists") then return false end
  local sv = SV()
  if sv.mode == "account" then return false end
  local from = sv.chars[fromKey or Prefs.CharKey() or ""] or Prefs.Lists()
  sv.account = Prefs.CopyLists(from, nil)
  sv.account.name = nil
  sv.mode = "account"
  CobysLootSweeper.Runs.LetGoKept()
  Changed()
  return true
end

-- UsePerCharacter(copyToEveryone): back to a list per character. Every
-- character seen so far, and every one seen later, starts with a copy of
-- the account lists (copyToEveryone) or with empty lists.
function Prefs.UsePerCharacter(copyToEveryone)
  if CobysLootSweeper.Utilities.Guarded("split lists") then return false end
  local sv = SV()
  if sv.mode ~= "account" then return false end
  local base = copyToEveryone and Prefs.CopyLists(sv.account) or Prefs.NormalizeLists(nil)
  base.name = nil
  for key, lists in pairs(sv.chars) do sv.chars[key] = Prefs.CopyLists(base, lists.name) end
  sv.seed = Prefs.CopyLists(base)
  sv.account = nil
  sv.mode = "character"
  local key, display = Prefs.CharKey()
  if key and not sv.chars[key] then sv.chars[key] = Prefs.CopyLists(base, display) end
  Changed()
  return true
end

-- Every entry of the lists in use, for the settings list: { list, id, label }
function Prefs.Entries()
  local lists = Prefs.Lists()
  local out = {}
  local function Add(list, map)
    for id, label in pairs(map) do out[#out + 1] = { list = list, id = id, label = label } end
  end
  Add("keep", lists.keep)
  Add("sell", lists.sell)
  Add("allowed", lists.allowed)
  for _, kind in ipairs(Prefs.BLOCK_KINDS) do Add(kind, lists.blocked[kind]) end
  return out
end
