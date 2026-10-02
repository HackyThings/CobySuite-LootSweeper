-------------------------------------------------------------------------------
-- MainWindow: the one Loot Sweeper window (design section 3)
--
-- At the top, the Overview (UI/Overview.lua): a live status banner with
-- Start / Stop, and five tiles: Vendor, Post, Protected, History and
-- Ignored. They pick the list below; History and Ignored swap in their own
-- views. The
-- list: item (icon in its quality's color), iLvl (gear only), vendor value,
-- AH value, and why (colored by kind: green to sell, gold to post, orange
-- when protected, tan when it's the player's call), with a picture and a
-- line when it is empty. The footer's action follows where the player
-- stands: at a vendor on the Vendor tab "Bulk sell..." opens BulkSell's
-- presets, custom choices and plan preview, with an optional question, and
-- shows progress and Stop while selling; on the Post tab "Vendor these
-- instead..." at a vendor, "Check prices with Auctionator" at the auction
-- house. The
-- note line shows the seller's last message, another addon that also sells,
-- or that no price addon is installed. Right-click a row: Use token... (a
-- token for this class), Automatic, Keep or Sell, and Remember for future
-- copies. Shift-click a row puts its link in chat. Between the tiles and the
-- list, the run picker: All runs, or one run's loot (the active run first,
-- then newest, with when it ran), and the tiles, the list, Sell and Forget
-- then work on that run alone. On the Vendor tab a row of quick buttons
-- (QuickSell: Junk, Bound gear, Other, Tradeable, Warbound, Can't sell) sits
-- over the footer. Built at ADDON_LOADED (never in combat).
-------------------------------------------------------------------------------
local UIModule = {}
CobysLootSweeper.UI = UIModule

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Events = CobysLootSweeper.Events
local Utilities = CobysLootSweeper.Utilities
local SortDir = CobySuite_CobysLootSweeper.SortDir

local WINDOW_NAME = "CobysLootSweeperWindow"
local PAD = 12
local ROW_HEIGHT = 24
local ICON_SIZE = 20
local OVERVIEW_TOP = -28
local LIST_BOTTOM = 62
local VENDOR_LIST_BOTTOM = 96   -- room for the quick-sell row
local SCROLLBAR_WIDTH = 10
local RUN_BAR_H = 32

local COLUMNS = {
  { key = "name", label = "Item", width = 200, sortable = true },
  { key = "ilvl", label = "iLvl", width = 44, justify = "RIGHT", sortable = true,
    tooltip = "Item level, for gear" },
  { key = "vendor", label = "Vendor", width = 70, justify = "RIGHT", sortable = true,
    tooltip = "What a vendor pays for everything in this row" },
  { key = "ah", label = "AH", width = 70, justify = "RIGHT", sortable = true,
    tooltip = "The auction house estimate for everything in this row after the 5% cut, from your price addon. A sale isn't promised." },
  { key = "why", label = "Why", stretch = true, sortable = true },
}

local window, header, scrollBox, scrollBar, runButton, emptyText, emptyIcon, runPicker, runInfo
local footer = {}
local groupFilter = nil   -- a quick-sell group shown alone while its confirmation is up
local runFilter = nil     -- nil: every run; else a run ID (Pile.OTHER: loot with no run)
local planRows = nil      -- the Bulk sell panel's plan: the list previews exactly these rows
local runSignature = nil
local currentTab = "vendor"
local sortKey, sortAscending = "vendor", false
local rememberChoice = false
local dockedTo = nil

local function Pile() return CobysLootSweeper.Pile end
local function Seller() return CobysLootSweeper.Seller end

-------------------------------------------------------------------------------
-- Sorting the visible rows
-------------------------------------------------------------------------------
local SORT_VALUE = {
  name = function(row) return (row.facts.name or ""):lower() end,
  ilvl = function(row) return row.facts.level or -1 end,
  vendor = function(row) return row.vendorValue or 0 end,
  ah = function(row) return row.ahValue or -1 end,
  why = function(row) return row.reason or "" end,
}

local function Compare(a, b)
  local get = SORT_VALUE[sortKey] or SORT_VALUE.vendor
  local va, vb = get(a), get(b)
  if va ~= vb then
    if sortAscending then return va < vb end
    return va > vb
  end
  return (a.facts.name or "") < (b.facts.name or "")
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
local function QualityColor(quality)
  local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if c then return c.r, c.g, c.b end
  return unpack(U.Colors.HIGHLIGHT_WHITE)
end

local function EnsureCells(row)
  if row.cells then return end
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
  row.IconFrame = row:CreateTexture(nil, "BORDER")
  row.IconFrame:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -1, 1)
  row.IconFrame:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 1, -1)
  UI.AddHoverHighlight(row)
end

local function LayoutCells(row)
  local x = 0
  for i, col in ipairs(header:GetColumns()) do
    local text = row.cells[i]
    if not text then break end
    local width = col.width or 60
    text:ClearAllPoints()
    if col.key == "name" then
      row.Icon:ClearAllPoints()
      row.Icon:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      text:SetPoint("LEFT", row, "LEFT", x + ICON_SIZE + 8, 0)
      text:SetWidth(math.max(width - ICON_SIZE - 12, 10))
    elseif col.stretch then
      text:SetPoint("LEFT", row, "LEFT", x + 6, 0)
      text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    else
      text:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      text:SetWidth(math.max(width - 10, 10))
    end
    x = x + width
  end
end

-- The Why column's color: what kind of answer it is
local function WhyColor(data)
  local C = U.Colors
  if data.bucket == "vendor" then return C.SAGE_GREEN end
  if data.bucket == "post" then return C.STATUS_GOLD end
  if data.pref == "keep" then return C.LIGHT_GRAY end
  if data.hard then return C.CAUTION_ORANGE end
  return C.SAND_TAN
end

local function PaintRow(row, data)
  row.data = data
  local facts = data.facts
  row.Icon:SetTexture(facts.icon or 134400)
  local r, g, b = QualityColor(facts.quality)
  row.IconFrame:SetColorTexture(r, g, b, 0.9)
  local name = facts.name or ("item " .. tostring(facts.itemID))
  local units = data.units or facts.count or 1
  if units > 1 then name = name .. " x" .. units end
  row.cells[1]:SetText(name)
  row.cells[1]:SetTextColor(r, g, b)
  row.cells[2]:SetText(facts.level and tostring(facts.level) or "")
  row.cells[3]:SetText(Utilities.GoldShort(data.vendorValue))
  -- AH: the lot's estimate after the cut; "warbound" or "bound" when the AH
  -- won't take it (Rules gives those no estimate), "-" when no price addon
  -- knows it
  local gray = U.Colors.LABEL_GRAY
  if data.ahValue then
    row.cells[4]:SetText(Utilities.GoldShort(data.ahValue))
    row.cells[4]:SetTextColor(unpack(U.Colors.HIGHLIGHT_WHITE))
  else
    row.cells[4]:SetText(facts.accountBound and "warbound" or (facts.bound and "bound" or "-"))
    row.cells[4]:SetTextColor(gray[1], gray[2], gray[3])
  end
  local why = data.reason or ""
  if data.pref then why = why .. (data.remembered and " (remembered)" or "") end
  row.cells[5]:SetText(why)
  local c = WhyColor(data)
  row.cells[5]:SetTextColor(c[1], c[2], c[3])
  U.AddAlternatingRowBg(row, data.index or 0)
end

local ShowMenu   -- forward

local function InitRow(row, data)
  if not row.cells then
    EnsureCells(row)
    UI.AddItemTooltip(row, function(self) return self.data and self.data.facts.link end, "ANCHOR_RIGHT")
    -- Under the item's own tooltip: the whole Why (its column can cut it
    -- short) and what the clicks do
    row:HookScript("OnEnter", function(self)
      if not self.data or not GameTooltip:IsOwned(self) then return end
      local why = self.data.reason
      if why and why ~= "" then
        if self.data.pref then why = why .. (self.data.remembered and " (remembered)" or "") end
        local c = WhyColor(self.data)
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        GameTooltip:AddLine("Why: " .. why, c[1], c[2], c[3], true)
      end
      GameTooltip_AddInstructionLine(GameTooltip, "Right-click for choices. Shift-click to link in chat.")
      GameTooltip:Show()
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if not self.data then return end
      if button == "RightButton" then
        ShowMenu(self, self.data)
      elseif IsModifiedClick("CHATLINK") and self.data.facts.link then
        CobySuite_CobysLootSweeper.Chat.PutInChat(self.data.facts.link)
      end
    end)
  end
  LayoutCells(row)
  PaintRow(row, data)
end

-------------------------------------------------------------------------------
-- The item menu
-------------------------------------------------------------------------------
-- A grouped row's choice goes to every copy in it
local function SetPref(data, value)
  for _, copy in ipairs(data.copies or { data }) do
    CobysLootSweeper.Prefs.Set(copy.entry, value, rememberChoice and value ~= nil)
  end
end

-- Keep: every copy of the item, on this character (or every character with
-- account-wide lists), leaves Loot Sweeper for good
local function KeepItem(data)
  local link = data.facts.link or data.entry.link
  CobysLootSweeper.Prefs.Keep(data.entry.itemID, link)
  CobysLootSweeper.Utilities.Message(string.format("Keeping %s: Loot Sweeper won't list it again. /ls kept undoes it.",
    link or data.facts.name or "it"))
end

local function IgnoreRow(data)
  local guids = {}
  for _, copy in ipairs(data.copies or { data }) do
    copy.entry.runName = copy.runName   -- shown on the Ignored tab, whatever happens to the run
    guids[#guids + 1] = copy.guid
  end
  CobysLootSweeper.Runs.Ignore(guids)
end

ShowMenu = function(owner, data)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(data.facts.name or "Item")
    if data.facts.classToken then
      local use = root:CreateButton("Use token...", function() CobysLootSweeper.UseToken.Open(data) end)
      if InCombatLockdown() then use:SetEnabled(false) end
      root:CreateDivider()
    end
    local function Is(value) return function() return data.pref == value end end
    root:CreateRadio("Automatic", Is(nil), function() SetPref(data, nil) end)
    local keep = root:CreateButton("Keep", function() KeepItem(data) end)
    keep:SetTooltip(function(tooltip)
      GameTooltip_AddNormalLine(tooltip, "Keep every copy of this item: Loot Sweeper lets go of them now and never lists it again.")
    end)
    local sell = root:CreateRadio("Sell", Is("sell"), function() SetPref(data, "sell") end)
    if data.hard and data.bucket ~= "vendor" then
      sell:SetEnabled(false)
      sell:SetTooltip(function(tooltip) GameTooltip_AddNormalLine(tooltip, "Loot Sweeper protects this one: " .. (data.reason or "")) end)
    end
    root:CreateCheckbox("Remember Sell for future copies", function() return rememberChoice end,
      function() rememberChoice = not rememberChoice end)
    root:CreateDivider()
    local copies = #(data.copies or { data })
    local ignore = root:CreateButton(copies > 1 and string.format("Ignore these %d", copies) or "Ignore",
      function() IgnoreRow(data) end)
    ignore:SetTooltip(function(tooltip)
      GameTooltip_AddNormalLine(tooltip, "Loot Sweeper stops listing this copy; it stays in your bags. Find it on the Ignored tab to un-ignore it. Future copies are sorted as usual.")
    end)
  end)
end

-------------------------------------------------------------------------------
-- The Overview (banner and tiles) and the empty list
-------------------------------------------------------------------------------
-- A run's name in the picker and the banner
local function RunLabel(r)
  if r.id == Pile().OTHER then return "Loot from opened boxes" end
  return r.name or ("Run " .. r.id)
end

local function RunTimes(r)
  if r.active then return "Tracking now" end
  local started, ended = Utilities.When(r.startedAt), Utilities.When(r.endedAt)
  if started and ended then
    -- "From today 4:30 PM to 5:10 PM": the day once when both are the same day
    local sameDay = started:match("^(%a+) ") == ended:match("^(%a+) ") and started:find(":") ~= nil
    return "From " .. started .. " to " .. (sameDay and ended:gsub("^%a+ ", "") or ended)
  end
  if started then return "Started " .. started end
  return nil
end

local function RunTooltip(r)
  local times = RunTimes(r)
  if r.history then
    return string.format("%s%d looted, %d sold for %s.", times and (times .. ". ") or "", r.count, r.sold,
      Utilities.Money(r.copper))
  end
  local parts = {}
  if r.vendorCount > 0 then parts[#parts + 1] = string.format("%d to sell (%s)", r.vendorCount, Utilities.Money(r.vendorValue)) end
  if r.postCount > 0 then parts[#parts + 1] = string.format("%d worth posting", r.postCount) end
  if r.keepCount > 0 then parts[#parts + 1] = string.format("%d protected", r.keepCount) end
  return (times and (times .. ". ") or "") .. table.concat(parts, ", ") .. "."
end

-- The picker's runs: those with loot waiting, or on the History tab every
-- run in the history
local function RunSource()
  if currentTab == "history" then return CobysLootSweeper.History.RunList() end
  return Pile().RunList()
end

local function SelectedRun()
  if runFilter == nil then return nil end
  for _, r in ipairs(RunSource()) do
    if r.id == runFilter then return r end
  end
  return nil
end

-- The picker lists the runs with loot waiting (on the History tab, every
-- run in the history); a run that is gone falls back to All runs, and with
-- no runs at all the picker hides
local function RefreshRuns(nothing)
  local list = RunSource()
  if runFilter ~= nil and not SelectedRun() then
    -- The confirmation's rows were the old run's (UI-01)
    CobysLootSweeper.QuickSell.CancelConfirm(true)
    runFilter = nil
    CobysLootSweeper.HistoryView.SetRun(nil)
    CobysLootSweeper.BulkSell.OnScopeChanged()
  end
  local shown = not nothing and #list > 0
  runPicker:SetShown(shown)
  runInfo:SetShown(shown)
  if not shown then return end
  local history = currentTab == "history"
  local total = 0
  for _, r in ipairs(list) do total = total + r.count end
  local labels, values = { string.format("All runs (%d)", total) }, { "all" }
  local tips = { history and "Every run in your history. Pick one to see only its loot."
    or "Every run's loot together. Pick one run to sell or forget only its loot." }
  local signature = { labels[1] }
  for _, r in ipairs(list) do
    labels[#labels + 1] = string.format("%s (%d)", RunLabel(r), r.count)
    values[#values + 1] = r.id
    tips[#tips + 1] = RunTooltip(r)
    signature[#signature + 1] = labels[#labels] .. tips[#tips]
  end
  signature = table.concat(signature, "|")
  if signature ~= runSignature then
    runSignature = signature
    runPicker:InitAgain(labels, values, tips)
  end
  runPicker:SetValue(runFilter or "all")
  local r = SelectedRun()
  -- On the History tab the line beside the picker is the totals, and stops
  -- short of the search box on the same row
  runInfo:ClearAllPoints()
  runInfo:SetPoint("LEFT", runPicker, "RIGHT", 10, 0)
  local search = history and CobysLootSweeper.HistoryView.SearchBox()
  if search then
    runInfo:SetPoint("RIGHT", search, "LEFT", -12, 0)
    runInfo:SetText(CobysLootSweeper.HistoryView.TotalsText(runFilter))
  else
    runInfo:SetPoint("RIGHT", window, "RIGHT", -PAD - 4, 0)
    if r then
      runInfo:SetText(RunTimes(r) or "")
    else
      runInfo:SetText(string.format("%d %s with loot waiting", #list, #list == 1 and "run" or "runs"))
    end
  end
end

local function RefreshOverview()
  local Runs = CobysLootSweeper.Runs
  local r = SelectedRun()
  local model = CobysLootSweeper.Overview.Model(Pile().Summary(runFilter), Runs.Active(), Runs.IsPreparing(),
    Seller().State(), Seller().MerchantReady(), r and RunLabel(r), CobysLootSweeper.History.Totals(runFilter),
    CobysLootSweeper.IgnoredView.Count(), CobysLootSweeper.Fences.Paused())
  runButton:SetText(model.action)
  runButton.action = model.action
  CobysLootSweeper.Overview.Paint(model, currentTab)
end

local EMPTY = {
  vendor = "No run loot is ready to sell. The Protected tab says what is held back, and why.",
  post = "Nothing worth posting right now.",
  keep = "Nothing protected. Loot Sweeper lists what it won't sell by itself here, with the reason.",
}
-- With no loot at all, the list shows how Loot Sweeper works in three steps
local STEPS = {
  { icon = CobysLootSweeper.ICON, title = "Enter an old dungeon or raid",
    text = "Tracking starts by itself in most of them. If it doesn't, or anywhere else, press Start." },
  { icon = "Interface\\Icons\\INV_Shield_06", title = "Loot as usual",
    text = "Only what you pick up now counts. What you already carry is never touched." },
  { icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Sell at any vendor",
    text = "Click the Loot Sweeper button on the vendor window, then pick what to sell." },
}

-- Nothing at all: the three steps, and no header, Forget or action to act
-- on. An empty tab of a pile: its picture and line
local PaintSteps   -- forward (defined with the steps it paints)

local function RefreshEmpty(rows)
  local s = Pile().Summary()
  local nothing = s.vendor.count + s.post.count + s.keep.count == 0
  local text = (not nothing and #rows == 0) and EMPTY[currentTab] or nil
  emptyText:SetText(text or "")
  emptyText:SetShown(text ~= nil)
  emptyIcon:SetShown(text ~= nil)
  window.Steps:SetShown(nothing)
  if nothing then PaintSteps(CobysLootSweeper.Runs.Active() ~= nil or CobysLootSweeper.Runs.IsPreparing()) end
  header:SetShown(not nothing)
  footer.forget:SetShown(not nothing)
  footer.forget:SetText(runFilter and "Forget this run" or "Forget remaining loot")
  return nothing
end

-------------------------------------------------------------------------------
-- Footer
-------------------------------------------------------------------------------
local function VendorAction()
  local state = Seller().State()
  local s = Pile().Summary(runFilter)
  if state.phase == "selling" then
    return string.format("Selling %d of %d...", state.sold + 1, state.total), false, true
  end
  if not Seller().MerchantReady() then return "Visit a vendor to sell", false, false end
  if state.phase == "paused" then return "Sell the next batch", true, true end
  if s.vendor.count + s.post.count + s.keep.count == 0 then return "Nothing to sell", false, false end
  if InCombatLockdown() then return "Leave combat to sell", false, false end
  if not Seller().IsQuiet() then return "Waiting for the vendor...", false, false end
  return "Bulk sell...", true, false
end

local function FooterNote()
  local state = Seller().State()
  if state.message and state.phase ~= "selling" then return state.message end
  local others = Seller().OtherSellers()
  if #others > 0 and Seller().MerchantReady() then
    return table.concat(others, ", ") .. " is also selling items. Loot Sweeper protects only its own sales."
  end
  if #CobysLootSweeper.Prices.Sources() == 0 then
    return "No price addon found, so most tradeable loot stays in Protected. Auctionator can price it."
  end
  return ""
end

local function RefreshFooter(rows)
  local note = FooterNote()
  local hint = ""
  footer.action:Hide()
  footer.stop:Hide()
  if currentTab == "vendor" then
    local text, enabled, stoppable = VendorAction()
    footer.action:SetText(text)
    footer.action:SetEnabled(enabled)
    footer.action:Show()
    footer.stop:SetShown(stoppable)
    if #rows > 0 then hint = "Use Tradeable to sell one at a time, or Bulk sell... to review a group." end
  elseif currentTab == "post" and #rows > 0 and Seller().MerchantReady() then
    -- At a vendor the player may sell them there instead (Task #121)
    footer.action:SetText("Vendor these instead...")
    footer.action:SetEnabled(Seller().State().phase ~= "selling" and not InCombatLockdown())
    footer.action:Show()
    hint = "AH values are estimates, not promised sale prices."
  elseif currentTab == "post" and #rows > 0 then
    local hasAuctionator = CobysLootSweeper.Prices.Installed("Auctionator")
    footer.action:SetText(hasAuctionator and "Check prices with Auctionator" or "Post with your auction tools")
    footer.action:SetEnabled(hasAuctionator and CobysLootSweeper.Fences.IsAuctionOpen())
    footer.action:Show()
    hint = "AH values are estimates, not promised sale prices."
  end
  footer.note:SetText(note ~= "" and note or hint)
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
-- The tab's rows, one per stack or item (what the seller and totals read)
local function CurrentRows()
  if planRows and (currentTab == "vendor" or currentTab == "post") then
    local out = {}
    for i, row in ipairs(planRows) do out[i] = row end
    table.sort(out, Compare)
    return out
  end
  return Pile().Bucket(currentTab, Compare, runFilter, currentTab == "vendor" and groupFilter or nil)
end

-- The rows shown: identical copies (same item, answer and choice) as one
-- row, "Mantle x2" with the values added up, sorted like any row
local function DisplayRows(rows)
  local groups, byKey = {}, {}
  for _, row in ipairs(rows) do
    local key = table.concat({ tostring(row.facts.link or row.facts.itemID), row.reason or "", row.pref or "" }, "|")
    local g = byKey[key]
    if not g then
      g = setmetatable({ copies = {}, units = 0, vendorValue = 0, value = 0 }, { __index = row })
      byKey[key] = g
      groups[#groups + 1] = g
    end
    g.copies[#g.copies + 1] = row
    g.units = g.units + (row.facts.count or 1)
    g.vendorValue = g.vendorValue + (row.vendorValue or 0)
    g.value = g.value + (row.value or 0)
    if row.ahValue then g.ahValue = (rawget(g, "ahValue") or 0) + row.ahValue end
  end
  table.sort(groups, Compare)
  for i, g in ipairs(groups) do g.index = i end
  return groups
end

function UIModule.Refresh()
  if not window or not window:IsShown() then return end
  local all = Pile().Summary()
  local history = currentTab == "history"
  local ignored = currentTab == "ignored"
  RefreshRuns((all.vendor.count + all.post.count + all.keep.count == 0 and not history) or ignored)
  CobysLootSweeper.HistoryView.SetShown(history)
  CobysLootSweeper.IgnoredView.SetShown(ignored)
  if history or ignored then
    for _, f in ipairs({ header, scrollBox, scrollBar, emptyText, emptyIcon, window.Steps, footer.action,
                         footer.stop, footer.forget, footer.note }) do f:Hide() end
    CobysLootSweeper.QuickSell.SetShown(false)
    RefreshOverview()
    return
  end
  scrollBox:Show()
  scrollBar:Show()
  footer.note:Show()
  local vendorTab = currentTab == "vendor"
  scrollBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - SCROLLBAR_WIDTH - 4, vendorTab and VENDOR_LIST_BOTTOM or LIST_BOTTOM)
  footer.note:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD + 2, vendorTab and 72 or 42)
  footer.note:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 4, vendorTab and 72 or 42)
  local rows = CurrentRows()
  local provider = CreateDataProvider(DisplayRows(rows))
  scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
  RefreshOverview()
  local nothing = RefreshEmpty(rows)
  RefreshFooter(rows)
  CobysLootSweeper.QuickSell.SetShown(vendorTab and not nothing)
  if vendorTab then CobysLootSweeper.QuickSell.Refresh(Pile().Summary(runFilter)) end
  if nothing then
    footer.action:Hide()
    footer.stop:Hide()
  end
end

-- The run picker's choice ("all" or a run ID); a confirmation for the old
-- run's rows is dropped first, so Sell never sells rows no longer shown (UI-01)
function UIModule.SetRunFilter(value)
  local nextFilter = value ~= "all" and value or nil
  local changed = nextFilter ~= runFilter
  if changed then CobysLootSweeper.QuickSell.CancelConfirm(true) end
  runFilter = nextFilter
  CobysLootSweeper.HistoryView.SetRun(runFilter)
  if changed then CobysLootSweeper.BulkSell.OnScopeChanged() end
  UIModule.Refresh()
end
function UIModule.RunFilter() return runFilter end

-- SetPlanRows(rows or nil): the Bulk sell panel's preview
function UIModule.SetPlanRows(rows)
  planRows = rows
  UIModule.Refresh()
end

function UIModule.SetTab(key)
  if key ~= currentTab then CobysLootSweeper.QuickSell.CancelConfirm() end
  currentTab = key
  UIModule.Refresh()
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
local function OnAction()
  if currentTab == "vendor" then
    if Seller().State().phase == "paused" then
      Seller().Start({})
    else
      CobysLootSweeper.BulkSell.Open()
    end
  elseif currentTab == "post" and Seller().MerchantReady() then
    CobysLootSweeper.BulkSell.Open("post")
  elseif currentTab == "post" then
    local names, seen = {}, {}
    for _, row in ipairs(CurrentRows()) do
      local name = row.facts.name
      if name and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    CobysLootSweeper.Prices.SearchAuctionator(names)
  end
  UIModule.Refresh()
end

local function OnRunButton()
  if runButton.action == "Stop" then
    CobysLootSweeper.Runs.Stop()
  else
    CobysLootSweeper.Runs.StartManual()
  end
end

-- Forget the whole pile, or with a run picked only that run's loot
local forgetPopup
local forgetRun = nil
local function ConfirmForget()
  if not forgetPopup then
    forgetPopup = UI.CreateDialogPopup({
      name = "CobysLootSweeperForgetPopup", title = "Forget remaining loot?", width = 380, height = 150,
      icon = CobysLootSweeper.ICON,
      confirmText = "Forget", cancelText = "Cancel", hidden = true,
      onConfirm = function() CobysLootSweeper.Runs.Forget(forgetRun) end,
    })
  end
  local r = SelectedRun()
  forgetRun = r and r.id or nil
  if r then
    forgetPopup.Title:SetText("Forget this run?")
    forgetPopup:SetBody(string.format("Loot Sweeper stops tracking the loot from %s. The items stay in your bags as ordinary items.", RunLabel(r)))
  else
    forgetPopup.Title:SetText("Forget remaining loot?")
    forgetPopup:SetBody("Loot Sweeper stops tracking the loot from every run. The items stay in your bags as ordinary items.")
  end
  forgetPopup:Show()
end
UIModule.ConfirmForget = ConfirmForget

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------
local BuildSteps   -- forward (BuildList calls it)

local function Gray(fontString)
  local gray = U.Colors.LABEL_GRAY
  fontString:SetTextColor(gray[1], gray[2], gray[3])
end

-- The three steps shown while there is no loot at all: an icon, a title in
-- gold and a line under it, each
BuildSteps = function()
  local steps = CreateFrame("Frame", nil, window)
  steps:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -20)
  steps:SetPoint("TOPRIGHT", header, "TOPRIGHT", -30, -20)
  steps:SetHeight(#STEPS * 58)
  steps.rows = {}
  local previous
  for i, def in ipairs(STEPS) do
    local icon = steps:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetTexture(def.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if previous then
      icon:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -20)
    else
      icon:SetPoint("TOPLEFT", steps, "TOPLEFT", 0, 0)
    end
    local title = steps:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -1)
    title:SetText(i .. ". " .. def.title)
    local text = steps:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    text:SetPoint("RIGHT", steps, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(def.text)
    Gray(text)
    local check = steps:CreateTexture(nil, "OVERLAY")
    check:SetSize(18, 18)
    check:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 5, -5)
    check:SetAtlas("UI-LFG-ReadyMark")
    check:Hide()
    steps.rows[i] = { icon = icon, title = title, text = text, check = check, def = def, index = i }
    previous = icon
  end
  steps:Hide()
  window.Steps = steps
end

-- The steps follow the player: with a run tracking, step 1 is done (checked,
-- dimmed) and step 2 is the one to do now (highlighted)
PaintSteps = function(tracking)
  local gold, white = U.Colors.STATUS_GOLD, U.Colors.HIGHLIGHT_WHITE
  local gray, light = U.Colors.LABEL_GRAY, U.Colors.LIGHT_GRAY
  local current = tracking and 2 or 1
  for i, row in ipairs(window.Steps.rows) do
    local done = i < current
    row.check:SetShown(done)
    row.icon:SetDesaturated(done)
    row.icon:SetAlpha(done and 0.5 or 1)
    local titleColor = done and gray or (i == current and gold or gold)
    row.title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
    row.title:SetText(i .. ". " .. row.def.title .. (i == current and tracking and "  (now)" or ""))
    local textColor = (i == current and not done) and white or (done and gray or light)
    row.text:SetTextColor(textColor[1], textColor[2], textColor[3])
  end
end

-- The banner and tiles; returns the y offset below them (where the run picker goes)
local function BuildTop()
  runButton = UI.CreateButton(window, {
    text = "Start", size = { 80, 22 },
    onClick = OnRunButton,
    tooltip = "Start tracks a run here. Stop ends tracking; the loot it found stays listed. Old dungeons and raids start and stop by themselves.",
  })
  local y = CobysLootSweeper.Overview.Build(window, runButton, function(key) UIModule.SetTab(key) end, OVERVIEW_TOP)
  -- Right-click the banner: never track where you stand
  local banner = CobysLootSweeper.Overview.frames.banner
  banner:EnableMouse(true)
  banner:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" then return end
    local place = CobysLootSweeper.Runs.Place()
    if not place then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      root:CreateTitle(place.name or "Here")
      root:CreateButton("Never track here", function() CobysLootSweeper.Runs.BlockHere() end)
    end)
  end)
  return y
end

-- The run picker and its line: when the picked run ran, or how many runs
local function BuildRunBar(top)
  runPicker = UI.CreateDropDown(window, {
    label = false, width = 280, height = 24, point = { "TOPLEFT", window, "TOPLEFT", PAD, top },
    onValueChanged = function(value) UIModule.SetRunFilter(value) end,
  })
  runInfo = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  runInfo:SetPoint("LEFT", runPicker, "RIGHT", 10, 0)
  runInfo:SetPoint("RIGHT", window, "RIGHT", -PAD - 4, 0)
  runInfo:SetJustifyH("LEFT")
  runInfo:SetWordWrap(false)
  Gray(runInfo)
  return top - RUN_BAR_H
end

local function BuildList(headerTop)
  header = CreateFrame("Frame", nil, window)
  Mixin(header, UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, headerTop)
  header:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD - SCROLLBAR_WIDTH - 4, headerTop)
  header:SetHeight(20)
  header:Init({
    columns = COLUMNS,
    persistenceKey = "main",
    persistence = { savedVariable = "COBYS_LOOT_SWEEPER_WINDOW_STATE", path = "columns" },
    utilities = U,
    fitToWidth = true,
    minStretch = 140,
    onSort = function(key, dir)
      sortKey, sortAscending = key, dir == SortDir.ASC
      UIModule.Refresh()
    end,
    onColumnResize = function()
      if scrollBox then scrollBox:ForEachFrame(function(row) if row.cells then LayoutCells(row) end end) end
    end,
  })
  header:SetSort(sortKey, SortDir.DESC)
  scrollBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - SCROLLBAR_WIDTH - 4, LIST_BOTTOM)
  local bar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  scrollBar = bar
  bar:SetHideIfUnscrollable(true)   -- no arrows over a list with nothing to scroll
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, bar, view)
  CobysLootSweeper.HistoryView.Build(window, headerTop, LIST_BOTTOM - 20, headerTop + RUN_BAR_H)
  CobysLootSweeper.IgnoredView.Build(window, headerTop, LIST_BOTTOM - 20, headerTop + RUN_BAR_H)
  -- Said over the empty list, under a picture: why nothing shows
  emptyIcon = window:CreateTexture(nil, "ARTWORK")
  emptyIcon:SetSize(56, 56)
  emptyIcon:SetPoint("TOP", scrollBox, "TOP", 0, -30)
  emptyIcon:SetTexture(CobysLootSweeper.ICON)
  emptyIcon:SetDesaturated(true)
  emptyIcon:SetAlpha(0.45)
  emptyIcon:Hide()
  emptyText = window:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  emptyText:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -12)
  emptyText:SetPoint("LEFT", scrollBox, "LEFT", 30, 0)
  emptyText:SetPoint("RIGHT", scrollBox, "RIGHT", -30, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetWordWrap(true)
  Gray(emptyText)
  emptyText:Hide()
  BuildSteps()
end

-- The note line over the buttons: Forget on the left, the action (and Stop
-- while selling) on the right
local function BuildFooter()
  footer.note = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  footer.note:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD + 2, 42)
  footer.note:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 4, 42)
  footer.note:SetJustifyH("LEFT")
  footer.note:SetWordWrap(false)
  Gray(footer.note)
  footer.action = UI.CreateButton(window, {
    text = "", size = { 220, 26 }, point = { "BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 4, 10 },
    onClick = OnAction,
  })
  footer.stop = UI.CreateButton(window, {
    text = "Stop selling", size = { 100, 22 }, point = { "RIGHT", footer.action, "LEFT", -6, 0 },
    onClick = function() Seller().Stop() end,
    tooltip = "Stop after the current sale. Tracking carries on.",
  })
  footer.forget = UI.CreateButton(window, {
    text = "Forget remaining loot", size = { 150, 20 }, fontSize = 10,
    point = { "BOTTOMLEFT", window, "BOTTOMLEFT", PAD + 2, 11 },
    onClick = ConfirmForget,
    tooltip = "Stop tracking this loot: every run's, or only the picked run's. The items stay in your bags.",
  })
end

local function Build()
  window = UI.CreateWindow({
    name = WINDOW_NAME,
    title = "Coby's Loot Sweeper",
    icon = CobysLootSweeper.ICON,
    width = 640, height = 620,
    resizable = { minWidth = 600, minHeight = 520, maxWidth = 1100, maxHeight = 1000 },
    escapeCloses = true,
    persist = { svTable = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end, key = "main" },
  })
  BuildList(BuildRunBar(BuildTop()))
  BuildFooter()
  CobysLootSweeper.QuickSell.Build(window, {
    RunFilter = function() return runFilter end,
    SetGroup = function(key, noRefresh)
      groupFilter = key
      if not noRefresh then UIModule.Refresh() end
    end,
  })
  window.HelpButton = UI.CreateHelpButton(window, {
    name = WINDOW_NAME .. "HelpButton",
    tooltip = "What Coby's Loot Sweeper can do",
    onClick = function() if CobysLootSweeper.Guide then CobysLootSweeper.Guide.Toggle() end end,
  })
  window:HookScript("OnShow", function()
    UIModule.Refresh()
    CobysLootSweeper.VendorButton.MarkSeen()
  end)
  window:HookScript("OnHide", function() dockedTo = nil end)
  UIModule.window = window
end

-------------------------------------------------------------------------------
-- Showing
-------------------------------------------------------------------------------
function UIModule.Toggle()
  if not window then return end
  if window:IsShown() then window:Hide() else UIModule.Open() end
end

function UIModule.Open(tab)
  if not window then return end
  if tab then currentTab = tab end
  if not dockedTo then window:RestoreState() end
  window:Show()
  UIModule.Refresh()
end

-- Beside a Blizzard window (the vendor or the auction house): on its right
-- when that fits on screen, else its left, else where it always went (its
-- right); our own frame is the one anchored, nothing of Blizzard's changes
function UIModule.OpenDocked(anchorFrame, tab)
  if not window then return end
  currentTab = tab or currentTab
  dockedTo = anchorFrame
  if not UI.DockBeside(window, anchorFrame, { gap = 12 }) then
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 12, 0)
  end
  window:Show()
  UIModule.Refresh()
end

function UIModule.CloseIfDocked(anchorFrame)
  if window and dockedTo == anchorFrame and window:IsShown() then window:Hide() end
end

function UIModule.IsShown() return window ~= nil and window:IsShown() end

-- For Source/Tests/Verify's scenes: the window, its row menu, and its rows
UIModule._test = {
  Window = function() return window end,
  Tab = function() return currentTab end,
  SetTabQuiet = function(tab) currentTab = tab end,
  ShowMenu = function(owner, data) return ShowMenu(owner, data) end,
  FirstRow = function()
    local first
    if scrollBox then scrollBox:ForEachFrame(function(row) if not first and row.data then first = row end end) end
    return first
  end,
  -- FindRow(test): the first shown row whose data passes test(data)
  FindRow = function(test)
    local found
    if scrollBox then
      scrollBox:ForEachFrame(function(row) if not found and row.data and test(row.data) then found = row end end)
    end
    return found
  end,
}

-- The Sell button waits a second after the vendor opens; repaint when that passes
local function BuildTicker()
  local ticker = CreateFrame("Frame", nil, window)
  local elapsed = 0
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.5 then return end
    elapsed = 0
    if currentTab == "vendor" and Seller().MerchantReady() and Seller().State().phase ~= "selling" then
      RefreshFooter(CurrentRows())
    end
  end)
end

-- Built once the SavedVariables are in (the column widths are read at
-- Init), during loading, so never in combat
EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", function()
  Build()
  BuildTicker()
end)

-------------------------------------------------------------------------------
-- Listeners
-------------------------------------------------------------------------------
local refresh = CobySuite_CobysLootSweeper.Utilities.Coalesce(0.1, function() UIModule.Refresh() end)
local listener = {}
function listener:ReceiveEvent() refresh:Call() end
CobysLootSweeper.EventBus:Register(listener, { Events.ViewUpdated, Events.RunChanged, Events.SellChanged, Events.InteractionChanged })
