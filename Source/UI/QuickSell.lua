-------------------------------------------------------------------------------
-- QuickSell: the row of quick buttons over the Vendor list
--
-- Junk, Bound gear and Other sell their part of the Vendor list in one go,
-- after a confirmation: a bar across the bottom of the window (over these
-- buttons, never over the list), and while it is up the list shows exactly
-- those items. Cancel, a tab change or closing the window drops it. Tradeable and Warbound open the one-at-a-time panel (Sell,
-- Skip, Stop): a friend, the auction house or another of the player's
-- characters might want them. Can't sell walks
-- through the run loot no vendor buys, to delete it one click at a time.
-- Every button follows the run picker (All runs or one run). Selling needs
-- the vendor open; deleting doesn't.
-------------------------------------------------------------------------------
local QuickSell = {}
CobysLootSweeper.QuickSell = QuickSell

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Utilities = CobysLootSweeper.Utilities

local GAP = 6

-- Button order, labels and what each one sells
QuickSell.DEFS = {
  { key = "junk", label = "Junk", noun = "junk item", nouns = "junk items",
    tip = "Every gray item from your runs, whatever the auction house says: players rarely buy them. Sold together after you confirm." },
  { key = "bound", label = "Bound gear", noun = "piece of bound gear", nouns = "pieces of bound gear",
    tip = "Soulbound weapons and armor from your runs whose look you already have. Gear near or above what you wear stays in Protected unless you turned that off in settings." },
  { key = "other", label = "Other", noun = "other bound item", nouns = "other bound items",
    tip = "Bound items that aren't gear: leftovers from old content that only a vendor wants now." },
  { key = "tradeable", label = "Tradeable", step = true, title = "Tradeable loot",
    note = "It can still be traded. Skip it to keep it for a friend or the auction house.",
    tip = "Items you could still trade or sell on the auction house, worth more to a vendor right now. You see them one at a time and choose Sell or Skip." },
  { key = "warbound", label = "Warbound", step = true, title = "Warbound loot",
    note = "It's bound to your warband. Skip it to keep it for another of your characters.",
    tip = "Items bound to your warband, such as another class's token: another of your characters could use them. You see them one at a time and choose Sell or Skip." },
  { key = "delete", label = "Can't sell", step = true,
    tip = "Run loot no vendor buys. You see them one at a time and choose Delete or Skip. Deleting is permanent." },
}

local q = { buttons = {} }

local function Plural(n, one, many) return n == 1 and one or many end

-- The confirmation bar: over the quick buttons and the footer, so the list
-- it describes stays in view
local function BuildBar(window)
  local bar = CreateFrame("Frame", nil, window)
  bar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 6)
  bar:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 6)
  bar:SetHeight(64)
  bar:SetFrameLevel(window:GetFrameLevel() + 30)
  bar:EnableMouse(true)
  local gold = U.Colors.STATUS_GOLD
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(0.08, 0.07, 0.04, 0.97)
  bar.line = bar:CreateTexture(nil, "BORDER")
  bar.line:SetPoint("TOPLEFT")
  bar.line:SetPoint("TOPRIGHT")
  bar.line:SetHeight(2)
  bar.line:SetColorTexture(gold[1], gold[2], gold[3], 0.9)
  bar.Sell = UI.CreateButton(bar, { text = "Sell", size = { 110, 26 }, point = { "RIGHT", bar, "RIGHT", -10, 0 },
    onClick = function() QuickSell.ConfirmSell() end })
  bar.Cancel = UI.CreateButton(bar, { text = "Cancel", size = { 90, 26 }, point = { "RIGHT", bar.Sell, "LEFT", -8, 0 },
    onClick = function() QuickSell.CancelConfirm() end })
  bar.Title = bar:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  bar.Title:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -12)
  bar.Title:SetPoint("RIGHT", bar.Cancel, "LEFT", -12, 0)
  bar.Title:SetJustifyH("LEFT")
  bar.Title:SetWordWrap(false)
  bar.Body = bar:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  bar.Body:SetPoint("TOPLEFT", bar.Title, "BOTTOMLEFT", 0, -6)
  bar.Body:SetPoint("RIGHT", bar.Cancel, "LEFT", -12, 0)
  bar.Body:SetJustifyH("LEFT")
  bar.Body:SetWordWrap(false)
  local gray = U.Colors.LABEL_GRAY
  bar.Body:SetTextColor(gray[1], gray[2], gray[3])
  bar:Hide()
  window:HookScript("OnHide", function() QuickSell.CancelConfirm() end)
  q.bar = bar
end


-- The bar's Sell: the rows it showed, taken before the bar closes (closing
-- clears them)
function QuickSell.ConfirmSell()
  if CobysLootSweeper.Utilities.Guarded("quick sell") then return end
  local pending = q.pending
  QuickSell.CancelConfirm()
  if pending and #pending > 0 then return CobysLootSweeper.Seller.Start(pending) end
  return false
end

-- noRefresh: the caller is refreshing the window already
function QuickSell.CancelConfirm(noRefresh)
  q.pending = nil
  if q.bar and q.bar:IsShown() then
    q.bar:Hide()
    q.ctx.SetGroup(nil, noRefresh)
  end
end

-- The confirmation for a bulk sale; the list shows the group while it is up
local function Confirm(def, rows, total)
  q.pending = rows
  q.bar.Title:SetText(string.format("Sell %d %s for %s?", #rows, Plural(#rows, def.noun, def.nouns), Utilities.Money(total)))
  q.bar.Body:SetText("Buyback keeps only your last 12 sales.")
  q.ctx.SetGroup(def.group or def.key)
  q.bar:Show()
end

QuickSell._test = {
  Confirm = function(...) return Confirm(...) end,
  IsConfirming = function() return q.bar ~= nil and q.bar:IsShown() end,
  Buttons = function() return q.buttons end,
}

local function OnClick(def)
  local runId = q.ctx.RunFilter()
  local Pile = CobysLootSweeper.Pile
  if def.key == "delete" then
    CobysLootSweeper.StepPanel.Open("delete", Pile.Deletable(runId), "Delete what no vendor buys")
    return
  end
  local rows = Pile.Bucket("vendor", function(a, b) return (a.vendorValue or 0) < (b.vendorValue or 0) end, runId, def.key)
  if def.step then
    CobysLootSweeper.StepPanel.Open("sell", rows, def.title, def.note)
    return
  end
  local total = 0
  for _, row in ipairs(rows) do total = total + (row.vendorValue or 0) end
  Confirm(def, rows, total)
end

-- Build(window, ctx): ctx.RunFilter() -> runId or nil, ctx.SetGroup(key, noRefresh)
function QuickSell.Build(window, ctx)
  q.ctx = ctx
  q.window = window
  BuildBar(window)
  for i, def in ipairs(QuickSell.DEFS) do
    q.buttons[i] = UI.CreateButton(window, {
      text = def.label, size = { 100, 22 }, fontSize = 10,
      onClick = function() OnClick(def) end,
      tooltip = def.tip,
    })
  end
  QuickSell.Layout()
  window:HookScript("OnSizeChanged", function() QuickSell.Layout() end)
end

-- The buttons share the row over the footer
function QuickSell.Layout()
  local window = q.window
  if not window then return end
  local n = #q.buttons
  local width = (window:GetWidth() or 0) - 24 - 4
  local each = math.max(60, (width - GAP * (n - 1)) / n)
  for i, b in ipairs(q.buttons) do
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14 + (i - 1) * (each + GAP), 42)
    b:SetWidth(each)
  end
end

function QuickSell.SetShown(shown)
  for _, b in ipairs(q.buttons) do b:SetShown(shown) end
end

-- Refresh(summary): counts on the buttons; selling needs a ready vendor
function QuickSell.Refresh(s)
  local Seller = CobysLootSweeper.Seller
  local canSell = Seller.MerchantReady() and not Seller.IsBusy() and Seller.State().phase ~= "paused"
    and not InCombatLockdown()
  for i, def in ipairs(QuickSell.DEFS) do
    local b = q.buttons[i]
    local count = def.key == "delete" and (s.deletable or 0) or ((s.groups and s.groups[def.key] or {}).count or 0)
    b:SetText(count > 0 and string.format("%s (%d)", def.label, count) or def.label)
    if def.key == "delete" then
      b:SetEnabled(count > 0 and not InCombatLockdown())
    else
      b:SetEnabled(count > 0 and canSell)
    end
  end
end

