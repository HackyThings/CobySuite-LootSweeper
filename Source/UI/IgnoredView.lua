-------------------------------------------------------------------------------
-- IgnoredView: the Ignored tab, the copies the player chose to ignore
--
-- A search box (item or run name) on the run bar's row, and the suite's
-- sortable table (CobySuite.UI.CreateSortTable) under it: item (icon and
-- quality color), iLvl, run, when it was ignored. Click a row to pick it;
-- Un-ignore (the button, or a row's right-click) puts the copy back in the
-- pile as it was (Runs.Unignore). Copies that left the bags drop off the
-- list by themselves (Ledger).
-------------------------------------------------------------------------------
local IgnoredView = {}
CobysLootSweeper.IgnoredView = IgnoredView

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Utilities = CobysLootSweeper.Utilities

local v = {}
local search = ""
local sortKey, ascending = "when", false
local picked = nil   -- the GUID of the row picked last

local function Name(row) return row.link and row.link:match("%[(.-)%]") or ("item " .. tostring(row.itemID)) end

local function Level(row)
  local link = row.link
  if type(link) ~= "string" then return nil end
  local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
  if not ok or not CobysLootSweeper.Facts.IsGearSlot(equipLoc) then return nil end
  local okL, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
  return okL and type(level) == "number" and level > 0 and level or nil
end

-- Rows(query): the ignored copies, as the table shows them, matching the
-- search (item or run name), in the order asked for
function IgnoredView.Rows(query)
  query = strlower(query or "")
  local rows = {}
  for _, it in ipairs(CobysLootSweeper.Runs.Ignored()) do
    local e = it.entry
    local row = {
      guid = it.guid, itemID = e.itemID, link = e.link, count = e.count + e.added, at = e.ignoredAt,
      run = e.runName or CobysLootSweeper.Runs.RunName(e.runId) or "",
    }
    row.name = Name(row)
    if query == "" or strlower(row.name):find(query, 1, true) or strlower(row.run):find(query, 1, true) then
      rows[#rows + 1] = row
    end
  end
  local value = {
    when = function(r) return r.at or 0 end, name = function(r) return strlower(r.name) end,
    ilvl = function(r) return Level(r) or -1 end, run = function(r) return strlower(r.run) end,
  }
  local get = value[sortKey] or value.when
  table.sort(rows, function(a, b)
    local va, vb = get(a), get(b)
    if va ~= vb then if ascending then return va < vb end return va > vb end
    return (a.at or 0) > (b.at or 0)
  end)
  return rows
end

local function Unignore(guid)
  if not guid then return end
  if CobysLootSweeper.Runs.Unignore(guid) and picked == guid then picked = nil end
end

local function ShowMenu(owner, row)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(row.name)
    local un = root:CreateButton("Un-ignore", function() Unignore(row.guid) end)
    un:SetTooltip(function(tooltip)
      GameTooltip_AddNormalLine(tooltip, "Back on the Loot Sweeper lists as it was before you ignored it.")
    end)
  end)
end

local function Quality(row)
  local q = row.link and C_Item.GetItemQualityByID(row.link)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and { c.r, c.g, c.b } or nil
end

-- Build(window, top, bottom, barTop): the table between the run bar and
-- the footer; the search box on the run bar's row (barTop)
function IgnoredView.Build(window, top, bottom, barTop)
  local frame = CreateFrame("Frame", nil, window)
  frame:SetPoint("TOPLEFT", window, "TOPLEFT", 12, top)
  frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, bottom)
  v.frame = frame
  v.hint = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  v.hint:SetPoint("LEFT", window, "TOPLEFT", 16, barTop - 13)
  v.hint:SetText("Copies you ignored. Right-click one, or pick it and press Un-ignore, to list it again.")
  local gray = U.Colors.LABEL_GRAY
  v.hint:SetTextColor(gray[1], gray[2], gray[3])
  v.search = UI.CreateSearchBox(frame, {
    name = "CobysLootSweeperIgnoredSearch", width = 170, point = { "TOPRIGHT", window, "TOPRIGHT", -16, barTop - 2 },
    placeholder = "Item or run",
    onSearch = function(text)
      search = text or ""
      IgnoredView.Refresh()
    end,
  })
  v.hint:SetPoint("RIGHT", v.search, "LEFT", -12, 0)
  v.table = UI.CreateSortTable(frame, {
    pool = 24, rowHeight = 22, minStretch = 140,
    columns = {
      { key = "name", label = "Item", stretch = true, text = function(r) return r.name .. (r.count > 1 and (" x" .. r.count) or "") end,
        color = Quality, icon = function(r) return C_Item.GetItemIconByID(r.itemID) end },
      { key = "ilvl", label = "iLvl", width = 44, justify = "RIGHT", tooltip = "Item level, for gear",
        text = function(r) local l = Level(r) return l and tostring(l) or "" end },
      { key = "run", label = "Run", width = 140, text = function(r) return r.run end },
      { key = "when", label = "Ignored", width = 110, text = function(r) return Utilities.When(r.at) or "" end },
    },
    persistence = { savedVariable = "COBYS_LOOT_SWEEPER_WINDOW_STATE", path = "columns", key = "ignored" },
    sortKey = sortKey, ascending = ascending,
    onSort = function(key, asc)
      sortKey, ascending = key, asc
      IgnoredView.Refresh()
    end,
    onRowEnter = function(frameRow, row)
      if not row.link then return end
      GameTooltip:SetOwner(frameRow, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(row.link)
      GameTooltip_AddInstructionLine(GameTooltip, "Right-click to un-ignore. Shift-click to link in chat.")
      GameTooltip:Show()
    end,
    onRowClick = function(frameRow, row, button)
      if button == "RightButton" then return ShowMenu(frameRow, row) end
      if IsModifiedClick("CHATLINK") and row.link then return CobySuite_CobysLootSweeper.Chat.PutInChat(row.link) end
      picked = row.guid
      IgnoredView.Refresh()
    end,
    selected = function(row) return row.guid == picked end,
    empty = "Nothing ignored. Right-click an item in the list and choose Ignore to hide one copy.",
  })
  v.table.frame:SetAllPoints(frame)
  v.unignore = UI.CreateButton(window, {
    text = "Un-ignore", size = { 120, 20 }, fontSize = 10,
    point = { "BOTTOMLEFT", window, "BOTTOMLEFT", 14, 11 },
    onClick = function() Unignore(picked) end,
    tooltip = "Put the picked copy back on the Loot Sweeper lists.",
  })
  frame:Hide()
  v.hint:Hide()
  v.unignore:Hide()
end

function IgnoredView.SetShown(shown)
  if not v.frame then return end
  v.frame:SetShown(shown)
  v.hint:SetShown(shown)
  v.unignore:SetShown(shown)
  if shown then IgnoredView.Refresh() end
end

function IgnoredView.Refresh()
  if not v.frame or not v.frame:IsShown() then return end
  local rows = IgnoredView.Rows(search)
  local still = false
  for _, row in ipairs(rows) do if row.guid == picked then still = true end end
  if not still then picked = nil end
  v.table:SetEmptyText(search ~= "" and "Nothing ignored matches that search."
    or "Nothing ignored. Right-click an item in the list and choose Ignore to hide one copy.")
  v.table:SetRows(rows)
  v.unignore:SetEnabled(picked ~= nil)
end

-- How many copies are ignored (the tile's count)
function IgnoredView.Count()
  return #CobysLootSweeper.Runs.Ignored()
end

local listener = {}
function listener:ReceiveEvent() IgnoredView.Refresh() end
CobysLootSweeper.EventBus:Register(listener, { CobysLootSweeper.Events.PileChanged })
