-------------------------------------------------------------------------------
-- Bulk: what a bulk sale the player picks would sell (Tasks #120 and #121;
-- the bag cleanup ideas and their review are in the design notes)
--
-- A pick is a preset or a Customize choice: { quality = { [q] = true },
-- kind = { [key] = true }, post = true }. Within one axis the ticks add up
-- (Greens or Blues); across the axes they narrow (green consumables); an
-- empty axis is any. The Post preset takes the Post list as it stands.
--
-- Plan(runId, pick, accept) walks the sorted rows of the whole pile, or of
-- the run the window's picker shows, and keeps every row the pick matches
-- that Rules.Eligible lets a reviewed sale take: the protections always
-- hold, an AH estimate above vendor never does (the player chose to
-- vendor), and items with no recent AH price or bound to the warband need
-- accept.noPrice or accept.warbound. What the pick matched but couldn't
-- take is counted by reason, and ignored copies are counted too, so the
-- panel can say what it left out and why.
-------------------------------------------------------------------------------
local Bulk = {}
CobysLootSweeper.Bulk = Bulk

local seams = {
  ClassName = function(classID)
    local ok, name = pcall(C_Item.GetItemClassInfo, classID)
    if ok and type(name) == "string" and not CobySuite_CobysLootSweeper.Utilities.IsSecret(name) then return name end
    return nil
  end,
}
Bulk._test = { seams = seams }

Bulk.QUALITIES = {
  { key = 0, label = "Junk" }, { key = 1, label = "Common" }, { key = 2, label = "Uncommon" },
  { key = 3, label = "Rare" }, { key = 4, label = "Epic" },
}

-- Kinds by item class (Enum.ItemClass); a class not listed is its own kind
Bulk.KINDS = {
  { key = "consumable", label = "Consumables", classes = { 0 } },
  { key = "trade", label = "Trade goods and reagents", classes = { 5, 7 } },
  { key = "armor", label = "Armor", classes = { 4 } },
  { key = "weapon", label = "Weapons", classes = { 2 } },
  { key = "recipe", label = "Recipes", classes = { 9 } },
  { key = "container", label = "Containers", classes = { 1 } },
  { key = "gem", label = "Gems and enhancements", classes = { 3, 8 } },
  { key = "misc", label = "Miscellaneous", classes = { 15 } },
}

local KIND_OF = {}
for _, k in ipairs(Bulk.KINDS) do
  for _, c in ipairs(k.classes) do KIND_OF[c] = k.key end
end

Bulk.PRESETS = {
  { key = "junk", label = "All junk", pick = { quality = { [0] = true } } },
  { key = "greens", label = "Greens", pick = { quality = { [2] = true } } },
  { key = "consumables", label = "Consumables", pick = { kind = { consumable = true } } },
  { key = "materials", label = "Materials", pick = { kind = { trade = true } } },
  { key = "post", label = "Post items", pick = { post = true } },
  { key = "everything", label = "Everything", pick = {} },
}

function Bulk.Preset(key)
  for _, p in ipairs(Bulk.PRESETS) do
    if p.key == key then return p end
  end
  return nil
end

-- KindOf(classID): the kind key ("class:<id>" for a class not listed)
function Bulk.KindOf(classID)
  if classID == nil then return "class:?" end
  return KIND_OF[classID] or ("class:" .. tostring(classID))
end

function Bulk.KindLabel(key)
  for _, k in ipairs(Bulk.KINDS) do
    if k.key == key then return k.label end
  end
  local id = tonumber(tostring(key):match("^class:(%d+)$"))
  return id and seams.ClassName(id) or "Other"
end

local function AxisMatches(set, value)
  if type(set) ~= "table" or next(set) == nil then return true end
  return set[value] == true
end

-- Matches(row, pick): the pick takes this row (eligibility aside)
function Bulk.Matches(row, pick)
  pick = pick or {}
  if pick.post and row.bucket ~= "post" then return false end
  local facts = row.facts or {}
  return AxisMatches(pick.quality, facts.quality) and AxisMatches(pick.kind, Bulk.KindOf(facts.classID))
end

local function RowEligible(row, settings, accept)
  return CobysLootSweeper.Rules.Eligible(row.entry, row.facts, row.quote, row.pref, settings, row.remembered, accept)
end

local function InRun(runId, entry)
  return runId == nil or (entry.runId or CobysLootSweeper.Pile.OTHER) == runId
end

-- Plan(runId, pick, accept) -> { rows (cheapest first), stacks, copper,
-- counts = { auction, noPrice, warbound, reagent, usable, consumable },
-- left = { [code] = n }, why = { [code] = a reason }, ignored }
function Bulk.Plan(runId, pick, accept)
  local settings = CobysLootSweeper.Rules.Settings()
  local plan = { rows = {}, copper = 0, left = {}, why = {}, ignored = 0,
                 counts = { auction = 0, noPrice = 0, warbound = 0, reagent = 0, usable = 0, consumable = 0 } }
  for _, row in ipairs(CobysLootSweeper.Pile.Rows()) do
    if InRun(runId, row.entry) and Bulk.Matches(row, pick) then
      local ok, code, reason, flags = RowEligible(row, settings, accept)
      if ok then
        plan.rows[#plan.rows + 1] = row
        plan.copper = plan.copper + (row.vendorValue or 0)
        for key in pairs(plan.counts) do
          if flags[key] then plan.counts[key] = plan.counts[key] + 1 end
        end
      else
        plan.left[code] = (plan.left[code] or 0) + 1
        plan.why[code] = plan.why[code] or reason
      end
    end
  end
  for _, ig in ipairs(CobysLootSweeper.Runs.Ignored()) do
    if InRun(runId, ig.entry) then plan.ignored = plan.ignored + 1 end
  end
  table.sort(plan.rows, function(a, b)
    if (a.vendorValue or 0) ~= (b.vendorValue or 0) then return (a.vendorValue or 0) < (b.vendorValue or 0) end
    return (a.facts.name or "") < (b.facts.name or "")
  end)
  plan.stacks = #plan.rows
  return plan
end

-- Options(runId, accept): each quality's and kind's own count and gold under
-- accept (every kind present, the listed ones first), for the Customize lists
function Bulk.Options(runId, accept)
  local settings = CobysLootSweeper.Rules.Settings()
  local out = { quality = {}, kind = {}, kinds = {} }
  for _, q in ipairs(Bulk.QUALITIES) do out.quality[q.key] = { count = 0, copper = 0 } end
  for _, k in ipairs(Bulk.KINDS) do
    out.kind[k.key] = { count = 0, copper = 0 }
    out.kinds[#out.kinds + 1] = k.key
  end
  for _, row in ipairs(CobysLootSweeper.Pile.Rows()) do
    if InRun(runId, row.entry) and RowEligible(row, settings, accept) then
      local q = out.quality[row.facts.quality]
      if q then q.count, q.copper = q.count + 1, q.copper + (row.vendorValue or 0) end
      local key = Bulk.KindOf(row.facts.classID)
      if not out.kind[key] then
        out.kind[key] = { count = 0, copper = 0 }
        out.kinds[#out.kinds + 1] = key
      end
      local k = out.kind[key]
      k.count, k.copper = k.count + 1, k.copper + (row.vendorValue or 0)
    end
  end
  return out
end

-- The pick saved on this character: { preset, quality, kind, custom,
-- warbound, noPrice }; never a sale, only what was ticked
function Bulk.Saved()
  local char = CobysLootSweeper.Runs.Char()
  if type(char.bulk) ~= "table" then char.bulk = { preset = "junk" } end
  local b = char.bulk
  if type(b.quality) ~= "table" then b.quality = {} end
  if type(b.kind) ~= "table" then b.kind = {} end
  if not Bulk.Preset(b.preset) then b.preset = "junk" end
  return b
end

-- The pick the saved choice stands for
function Bulk.PickOf(saved)
  if saved.custom then return { quality = saved.quality, kind = saved.kind } end
  return Bulk.Preset(saved.preset).pick
end

function Bulk.AcceptOf(saved)
  return { warbound = saved.warbound == true, noPrice = saved.noPrice == true }
end
