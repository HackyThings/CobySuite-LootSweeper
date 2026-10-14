-------------------------------------------------------------------------------
-- HistoryView: the History tab, everything your runs looted and what became
-- of it
--
-- A search box (item or run name) on the run picker's row, and a sortable
-- table right under it: when, item, iLvl, run, what happened. The totals line
-- (TotalsText: looted, sold and the gold it made, deleted) sits beside the
-- picker, where the window puts it. It follows the run picker. "Clear
-- history" empties it after asking; the loot still waiting is not touched.
-------------------------------------------------------------------------------
local HistoryView = {}
CobysLootSweeper.HistoryView = HistoryView

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Utilities = CobysLootSweeper.Utilities
local SortDir = CobySuite_CobysLootSweeper.SortDir

local ROW_HEIGHT = 22
local ICON_SIZE = 18
local SCROLLBAR_WIDTH = 10

local COLUMNS = {
  { key = "when", label = "When", width = 110, sortable = true },
  { key = "name", label = "Item", width = 280, sortable = true },
  { key = "qty", label = "Qty", width = 40, justify = "RIGHT", sortable = true, tooltip = "How many were looted" },
  { key = "ilvl", label = "iLvl", width = 44, justify = "RIGHT", sortable = true, tooltip = "Item level, for gear" },
  { key = "run", label = "Run", width = 100, sortable = true },
  { key = "outcome", label = "What happened", stretch = true, sortable = true },
}

local OUTCOME = {
  equipped = "Equipped", left = "Left your bags", ["let go"] = "Let go",
  used = "Used", combined = "Combined into another stack", kept = "Kept",
  ignored = "Ignored",
}

local v = {}
local sortKey, sortAscending = "when", false
local search = ""

local function Name(rec) return rec.link and rec.link:match("%[(.-)%]") or ("item " .. tostring(rec.itemID)) end

-- Gear's item level from its link (the looted copy's own level), cached per
-- link; nil for anything that isn't gear
local levels = {}
local function Level(rec)
  local link = rec.link
  if type(link) ~= "string" then return nil end
  if levels[link] == nil then
    local level = false
    local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
    if ok and CobysLootSweeper.Facts.IsGearSlot(equipLoc) then
      local okL, actual = pcall(C_Item.GetDetailedItemLevelInfo, link)
      if okL and type(actual) == "number" and actual > 0 then level = actual end
    end
    levels[link] = level
  end
  return levels[link] or nil
end
local function OutcomeText(rec)
  if rec.outcome == nil then return "Waiting", U.Colors.LABEL_GRAY end
  if rec.outcome == "sold" then return "Sold for " .. Utilities.Money(rec.copper or 0), U.Colors.SAGE_GREEN end
  if rec.outcome == "sold elsewhere" then
    return "Sold elsewhere for " .. Utilities.Money(rec.copper or 0), U.Colors.SAGE_GREEN
  end
  if rec.outcome == "deleted" then return "Deleted", U.Colors.CAUTION_ORANGE end
  return OUTCOME[rec.outcome] or rec.outcome, U.Colors.LIGHT_GRAY
end

local SORT_VALUE = {
  when = function(rec) return rec.at or 0 end,
  name = function(rec) return Name(rec):lower() end,
  qty = function(rec) return rec.count or 1 end,
  ilvl = function(rec) return Level(rec) or -1 end,
  run = function(rec) return (rec.run or ""):lower() end,
  outcome = function(rec) return (OutcomeText(rec)):lower() end,
}

local function Compare(a, b)
  local get = SORT_VALUE[sortKey] or SORT_VALUE.when
  local va, vb = get(a), get(b)
  if va ~= vb then
    if sortAscending then return va < vb end
    return va > vb
  end
  return (a.at or 0) > (b.at or 0)
end

local function LayoutCells(row)
  UI.LayoutRowCells(row, v.header, { iconKey = "name", iconSize = ICON_SIZE, inset = 10 })
end

local function InitRow(row, rec)
  if not row.cells then
    row.cells = {}
    for i, col in ipairs(COLUMNS) do
      local text = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
      text:SetJustifyH(col.justify or "LEFT")
      text:SetWordWrap(false)
      row.cells[i] = text
    end
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    UI.AddHoverHighlight(row)
    UI.AddItemTooltip(row, function(self) return self.rec and self.rec.link end, "ANCHOR_RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if not self.rec then return end
      if button == "RightButton" then return HistoryView.ShowMenu(self, self.rec) end
      if self.rec.link and IsModifiedClick("CHATLINK") then CobySuite_CobysLootSweeper.Chat.PutInChat(self.rec.link) end
    end)
  end
  row.rec = rec
  LayoutCells(row)
  row.Icon:SetTexture(C_Item.GetItemIconByID(rec.itemID) or 134400)
  row.cells[1]:SetText(Utilities.When(rec.at) or "")
  local quality = rec.link and C_Item.GetItemQualityByID(rec.link)
  row.cells[2]:SetText(Name(rec))
  UI.SetQualityColor(row.cells[2], quality)
  row.cells[3]:SetText(tostring(rec.count or 1))
  local level = Level(rec)
  row.cells[4]:SetText(level and tostring(level) or "")
  row.cells[5]:SetText(rec.run or "")
  local outcome, color = OutcomeText(rec)
  row.cells[6]:SetText(outcome)
  row.cells[6]:SetTextColor(color[1], color[2], color[3])
  U.AddAlternatingRowBg(row, rec.index or 0)
end

-- MenuFor(rec): "ignore" for a copy still listed, "unignore" for an
-- ignored copy still in the bags, else nil (nothing to offer)
function HistoryView.MenuFor(rec)
  local ledger = CobysLootSweeper.Runs.Ledger()
  if rec.outcome == nil and ledger.pile[rec.guid] then return "ignore" end
  if rec.outcome == "ignored" and ledger.ignored[rec.guid] then return "unignore" end
  return nil
end

-- A History row's right-click: Ignore or Un-ignore that copy
function HistoryView.ShowMenu(owner, rec, anchor)
  local action = HistoryView.MenuFor(rec)
  if not action then return end
  CobysLootSweeper.UI.OpenMenu(owner, function(_, root)
    root:CreateTitle(Name(rec))
    if action == "ignore" then
      root:CreateButton("Ignore", function()
        local entry = CobysLootSweeper.Runs.Ledger().pile[rec.guid]
        if entry then entry.runName = rec.run end
        CobysLootSweeper.Runs.Ignore({ rec.guid })
      end)
    else
      root:CreateButton("Un-ignore", function() CobysLootSweeper.Runs.Unignore(rec.guid) end)
    end
  end, anchor)
end

local clearPopup
local function ConfirmClear()
  if not clearPopup then
    clearPopup = UI.CreateDialogPopup({
      name = "CobysLootSweeperClearHistoryPopup", title = "Clear history?", width = 380, height = 150, danger = true,
      icon = CobysLootSweeper.ICON,
      body = "Every record and total on this tab is removed, for all runs. Loot still waiting to be sold is not touched.",
      confirmText = "Clear", cancelText = "Cancel", hidden = true,
      onConfirm = function() CobysLootSweeper.History.Clear() end,
    })
  end
  clearPopup:Show()
end
HistoryView._test = { ConfirmClear = ConfirmClear }

-- Build(window, top, bottom, barTop): the table between the run bar and the
-- footer; the search box on the run bar's row (barTop)
function HistoryView.Build(window, top, bottom, barTop)
  local frame = CreateFrame("Frame", nil, window)
  frame:SetPoint("TOPLEFT", window, "TOPLEFT", 12, top)
  frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, bottom)
  v.frame = frame
  v.search = UI.CreateSearchBox(frame, {
    name = "CobysLootSweeperHistorySearch", width = 170, point = { "TOPRIGHT", window, "TOPRIGHT", -16, barTop - 2 },
    placeholder = "Item or run",
    onSearch = function(text)
      search = text or ""
      HistoryView.Refresh()
    end,
  })
  local header = CreateFrame("Frame", nil, frame)
  Mixin(header, UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SCROLLBAR_WIDTH - 4, 0)
  header:SetHeight(20)
  header:Init({
    columns = COLUMNS,
    persistenceKey = "history",
    widthsVersion = 1,
    persistence = { savedVariable = "COBYS_LOOT_SWEEPER_WINDOW_STATE", path = "columns" },
    utilities = U,
    fitToWidth = true,
    minStretch = 120,
    onSort = function(key, dir)
      sortKey, sortAscending = key, dir == SortDir.ASC
      HistoryView.Refresh()
    end,
    onColumnResize = function()
      if v.scrollBox then v.scrollBox:ForEachFrame(function(row) if row.cells then LayoutCells(row) end end) end
    end,
  })
  header:SetSort(sortKey, SortDir.DESC)
  v.header = header
  local list = UI.CreateScrollList(frame, { initializeRow = InitRow, rowHeight = ROW_HEIGHT, visibility = "auto" })
  local scrollBox = list.box
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLLBAR_WIDTH - 4, 0)
  v.scrollBox = scrollBox
  v.empty = UI.CreateEmptyLabel(frame, {
    points = { { "TOPLEFT", scrollBox, "TOPLEFT", 30, -40 }, { "TOPRIGHT", scrollBox, "TOPRIGHT", -30, -40 } },
  })
  v.clear = UI.CreateButton(window, {
    text = "Clear History", size = { 120, 20 }, fontSize = 10,
    point = { "BOTTOMLEFT", window, "BOTTOMLEFT", 14, 11 },
    onClick = ConfirmClear,
    tooltip = "Remove every record and total on this tab. Loot still waiting to be sold stays.",
  })
  frame:Hide()
  v.clear:Hide()
end

function HistoryView.SetShown(shown)
  if not v.frame then return end
  v.frame:SetShown(shown)
  v.clear:SetShown(shown)
  if shown then HistoryView.Refresh() end
end

-- The totals line beside the run picker: all time, or the picked run's
function HistoryView.TotalsText(runId)
  local t = CobysLootSweeper.History.Totals(runId)
  if (t.looted or 0) == 0 and (t.copper or 0) == 0 then return "" end
  local gold = U.WrapColor(U.ColorToHex(U.Colors.STATUS_GOLD), Utilities.Money(t.copper or 0))
  local deleted = runId == nil and (t.deleted or 0) > 0 and string.format(", %d deleted", t.deleted) or ""
  local elsewhere = (t.elsewhere or 0) > 0 and string.format(" (%s of it sold elsewhere)", Utilities.Money(t.elsewhere)) or ""
  return string.format("%d looted, %d sold for %s%s%s", t.looted or 0, t.sold or 0, gold, elsewhere, deleted)
end

-- The search box, for the window's run bar layout
function HistoryView.SearchBox() return v.search end

-- Refresh(): the run picked last (SetRun) and the search box's text
function HistoryView.Refresh()
  if not v.frame or not v.frame:IsShown() then return end
  local records = CobysLootSweeper.History.Records(v.runId, search)
  table.sort(records, Compare)
  local list = {}
  for i, rec in ipairs(records) do
    -- the record itself carries its stripe index only in this list's copy
    list[i] = setmetatable({ index = i }, { __index = rec })
  end
  v.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
  v.clear:SetEnabled(CobysLootSweeper.History.HasAny())
  v.empty:SetText(#list == 0 and (search ~= "" and "Nothing matches that search."
    or "Nothing here yet. Loot from your runs is listed here, with what became of it.") or nil)
end

-- The picked run changed (nil: All runs)
function HistoryView.SetRun(runId)
  v.runId = runId
  HistoryView.Refresh()
end

local listener = {}
function listener:ReceiveEvent() HistoryView.Refresh() end
CobysLootSweeper.EventBus:Register(listener, { CobysLootSweeper.Events.HistoryChanged })
