-------------------------------------------------------------------------------
-- CobySuite.UI.CreateSortTable: a sortable table with expandable groups
--
-- A header with sortable, resizable columns fitted to the table's width
-- (CobySuite.UI.TableHeaderMixin with fitToWidth: the stretch column takes
-- what the others leave, never less than minStretch), and a fixed pool of
-- rows made at build, scrolled with FauxScrollFrameTemplate, so showing,
-- scrolling, sorting and resizing are safe in combat. Generalized from
-- Recollect's curator dashboard table (Task #68, 2026-10-01).
--
--   local t = CobySuite.UI.CreateSortTable(parent, {
--     pool = 30, rowHeight = 20, minStretch = 120,
--     columns = {
--       { key, label, width, stretch, justify, tooltip, sortable (default true),
--         text(row), color(row) -> { r, g, b }, icon(row) -> file ID, path or "atlas:<name>"
--         (the one column that shows an icon), load(row) (called when the row is painted) },
--     },
--     persistence = { savedVariable = "MY_SV", path = "windows", key = "steps" },  -- optional: column widths
--     sortKey = "status", ascending = true, onSort(key, ascending),
--     onRowEnter(frame, row), onRowClick(frame, row, mouseButton),
--     selected(row) -> true for the row painted as selected,
--     group(row) -> true for a group's header row: its first column takes the
--       row's whole width, in gold, with an open or closed arrow from open(row)
--     open(row) -> whether that group is open,
--     indent(row) -> pixels the first column's text moves right (a group's rows),
--     empty = "Nothing here",   -- a line over the table while it has no rows
--   })
--   t:SetRows(rows)   t:Refresh()   t:SetEmptyText(text)   t.frame   t.header
--
-- Rows are shown as given: sorting, filtering and which groups are open are
-- the caller's (onSort tells it the order asked for).
-------------------------------------------------------------------------------
local UI = CobySuite_CobysLootSweeper.UI
local U = CobySuite_CobysLootSweeper.Utilities

local HEADER_H = 20
local ICON = 16
local SCROLL_ROOM = 22
-- the objective tracker's plus and minus, as the collapsible headers use
local ARROW_OPEN, ARROW_CLOSED = "ui-questtrackerbutton-collapse-section", "ui-questtrackerbutton-expand-section"

local Table = {}
Table.__index = Table

-- Sets an icon that is a texture or "atlas:<name>"
local function SetIcon(texture, icon)
  local atlas = type(icon) == "string" and icon:match("^atlas:(.+)$")
  if atlas then
    texture:SetAtlas(atlas)
    texture:SetTexCoord(0, 1, 0, 1)
  else
    texture:SetTexture(icon or 134400)   -- INV_Misc_QuestionMark, for a row with no icon
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
end
UI.SetTableIcon = SetIcon

local function MakeRow(t, i)
  local row = CreateFrame("Button", nil, t.list)
  row:SetHeight(t.rowHeight)
  row:SetPoint("TOPLEFT", t.list, "TOPLEFT", 0, -(i - 1) * t.rowHeight)
  row:SetPoint("RIGHT", t.list, "RIGHT", 0, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.AddHoverHighlight(row)
  row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.Selected:SetAllPoints()
  local gold = U.Colors.STATUS_GOLD
  row.Selected:SetColorTexture(gold[1], gold[2], gold[3], 0.15)
  row.Selected:Hide()
  row.Arrow = row:CreateTexture(nil, "ARTWORK")
  row.Arrow:SetSize(14, 14)
  row.Arrow:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.Arrow:Hide()
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(ICON, ICON)
  row.cells = {}
  for c = 1, #t.columns do
    local text = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
    text:SetWordWrap(false)
    row.cells[c] = text
  end
  row:SetScript("OnEnter", function(self)
    if self.data and t.opts.onRowEnter then t.opts.onRowEnter(self, self.data) end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self, button)
    if self.data and t.opts.onRowClick then t.opts.onRowClick(self, self.data, button) end
  end)
  row:Hide()
  return row
end

local function BuildHeader(t, opts)
  local header = CreateFrame("Frame", nil, t.frame)
  Mixin(header, UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", t.frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", t.frame, "TOPRIGHT", -SCROLL_ROOM, 0)
  header:SetHeight(HEADER_H)
  local columns = {}
  for i, col in ipairs(opts.columns) do
    columns[i] = { key = col.key, label = col.label, width = col.width, stretch = col.stretch, justify = col.justify,
      tooltip = col.tooltip, sortable = col.sortable ~= false }
  end
  local p = opts.persistence
  header:Init({
    columns = columns, persistenceKey = p and p.key or nil,
    persistence = p and { savedVariable = p.savedVariable, path = p.path } or nil,
    utilities = U, headerHeight = HEADER_H, fitToWidth = true, minStretch = opts.minStretch or 120,
    onSort = function(key, dir)
      if opts.onSort then opts.onSort(key, dir == CobySuite_CobysLootSweeper.SortDir.ASC) end
    end,
    onColumnResize = function() t:Layout() end,
  })
  header:HookScript("OnSizeChanged", function() t:Layout() end)
  if opts.sortKey then
    header:SetSort(opts.sortKey, opts.ascending == false and CobySuite_CobysLootSweeper.SortDir.DESC or CobySuite_CobysLootSweeper.SortDir.ASC)
  end
  t.header = header
end

-- CreateSortTable(parent, opts): the table; every frame is made here
function UI.CreateSortTable(parent, opts)
  local t = setmetatable({ opts = opts, columns = opts.columns, rows = {}, pool = {}, rowHeight = opts.rowHeight or 20 },
    Table)
  for c, col in ipairs(opts.columns) do
    if col.icon and not t.iconColumn then t.iconColumn = c end
  end
  local frame = CreateFrame("Frame", nil, parent)
  t.frame = frame
  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H - 2)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLL_ROOM, 0)
  list:SetClipsChildren(true)
  t.list = list
  local scroll = CreateFrame("ScrollFrame", nil, frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, t.rowHeight, function() t:Paint() end)
  end)
  t.scroll = scroll
  t.Empty = frame:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  t.Empty:SetPoint("TOP", list, "TOP", 0, -24)
  t.Empty:SetWidth(360)
  t.Empty:SetWordWrap(true)
  local gray = U.Colors.LABEL_GRAY
  t.Empty:SetTextColor(gray[1], gray[2], gray[3])
  t.Empty:SetText(opts.empty or "")
  BuildHeader(t, opts)
  for i = 1, opts.pool or 30 do t.pool[i] = MakeRow(t, i) end
  frame:SetScript("OnSizeChanged", function() t:Layout() t:Refresh() end)
  return t
end

-- One row's cells under the header's columns (bounds from the last Layout)
local function LayoutRow(t, row)
  local bounds = t.bounds or {}
  for c, text in ipairs(row.cells) do
    local b, col = bounds[c], t.columns[c]
    text:ClearAllPoints()
    if b and col then
      text:Show()
      text:SetJustifyH(col.justify or "LEFT")
      local inset = 4
      if c == t.iconColumn then
        row.Icon:ClearAllPoints()
        row.Icon:SetPoint("LEFT", row, "LEFT", b.left + 4, 0)
        inset = ICON + 8
      end
      text:SetPoint("LEFT", row, "LEFT", b.left + inset, 0)
      text:SetWidth(math.max(b.width - inset - 4, 10))
    else
      text:Hide()
    end
  end
end

-- Places every row's cells under the header's columns
function Table:Layout()
  local header = self.header
  if header.FitColumns then pcall(header.FitColumns, header) end
  header:RepositionHeaders()
  self.bounds = header:GetColumnBounds()
  for _, row in ipairs(self.pool) do
    row.wasGroup = nil
    LayoutRow(self, row)
  end
  if self.rows then self:Paint() end
end

function Table:SetRows(rows)
  self.rows = rows or {}
  self:Refresh()
end

function Table:SetEmptyText(text)
  self.Empty:SetText(text or "")
end

-- How many rows fit now (never more than the pool)
function Table:Visible()
  local height = self.list:GetHeight() or 0
  return math.max(0, math.min(#self.pool, math.floor(height / self.rowHeight)))
end

function Table:Refresh()
  FauxScrollFrame_Update(self.scroll, #self.rows, self:Visible(), self.rowHeight)
  self.Empty:SetShown(#self.rows == 0)
  self:Paint()
end

local function Call(fn, row)
  if not fn then return nil end
  local ok, value = pcall(fn, row)
  return ok and value or nil
end

-- A group's header row: its title across the row, gold, with the arrow
local function PaintGroup(t, frame, data)
  local open = Call(t.opts.open, data)
  frame.Arrow:Show()
  frame.Arrow:SetAtlas(open and ARROW_OPEN or ARROW_CLOSED)
  frame.Icon:Show()
  frame.Icon:ClearAllPoints()
  frame.Icon:SetPoint("LEFT", frame.Arrow, "RIGHT", 4, 0)
  SetIcon(frame.Icon, Call(t.iconColumn and t.columns[t.iconColumn].icon, data))
  local first = frame.cells[1]
  first:ClearAllPoints()
  first:SetPoint("LEFT", frame.Icon, "RIGHT", 6, 0)
  first:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
  first:SetText(tostring(Call(t.columns[1].text, data) or ""))
  local gold = U.Colors.STATUS_GOLD
  first:SetTextColor(gold[1], gold[2], gold[3])
  for c = 2, #frame.cells do frame.cells[c]:SetText("") end
  frame.wasGroup = true
end

-- Paints the rows on screen from the scroll offset
function Table:Paint()
  local offset = FauxScrollFrame_GetOffset(self.scroll)
  local visible = self:Visible()
  local white = U.Colors.HIGHLIGHT_WHITE
  local iconCol = self.iconColumn and self.columns[self.iconColumn]
  for i, frame in ipairs(self.pool) do
    local index = offset + i
    local data = i <= visible and self.rows[index] or nil
    frame.data = data
    if not data then
      frame:Hide()
    else
      frame:Show()
      U.AddAlternatingRowBg(frame, index)
      frame.Selected:SetShown(Call(self.opts.selected, data) == true)
      if Call(self.opts.group, data) then
        PaintGroup(self, frame, data)
      else
        frame.Arrow:Hide()
        if frame.wasGroup then
          frame.wasGroup = nil
          LayoutRow(self, frame)
        end
        frame.Icon:SetShown(iconCol ~= nil)
        if iconCol then SetIcon(frame.Icon, Call(iconCol.icon, data)) end
        local indent = Call(self.opts.indent, data) or 0
        for c, col in ipairs(self.columns) do
          if col.load then Call(col.load, data) end
          local text = frame.cells[c]
          if c == 1 and self.bounds and self.bounds[1] then
            local b = self.bounds[1]
            local inset = (c == self.iconColumn and ICON + 8 or 4) + indent
            text:ClearAllPoints()
            text:SetPoint("LEFT", frame, "LEFT", b.left + inset, 0)
            text:SetWidth(math.max(b.width - inset - 4, 10))
            if c == self.iconColumn then
              frame.Icon:ClearAllPoints()
              frame.Icon:SetPoint("LEFT", frame, "LEFT", b.left + 4 + indent, 0)
            end
          end
          text:SetText(tostring(Call(col.text, data) or ""))
          local color = (col.color and Call(col.color, data)) or white
          text:SetTextColor(color[1], color[2], color[3])
        end
      end
    end
  end
end
