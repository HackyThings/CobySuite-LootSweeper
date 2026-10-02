-------------------------------------------------------------------------------
-- BulkSell: the Bulk sell panel (Tasks #120 and #121; the bag cleanup notes)
--
-- Opened at a vendor from the Vendor tab's "Bulk sell..." or the Post tab's
-- "Vendor these instead...", it sits beside the main window, whose list
-- previews exactly what the pick would sell (Post rows included). On top,
-- the presets as stat tiles (All junk, Greens, Consumables, Materials, Post
-- items, Everything); Customize opens two columns of ticks, by
-- quality and by kind, each with its count and gold (ticks add up within a
-- column and narrow across them). Two switches take warbound items and
-- items with no recent AH price, off by default. Below, the plan: stacks,
-- bag slots, gold, how many the AH values above vendor, the reagents and
-- the consumables you can use, and what was left out and why. One button
-- names the outcome ("Sell 21 stacks for 53g"), then one confirmation
-- (CreateDialogPopup, unless "Ask before a bulk sale" is off). The scope is
-- the main window's run picker; changing it repaints the plan and drops an
-- open confirmation. What is ticked is remembered per character, never a
-- sale. Built on first open, out of combat.
-------------------------------------------------------------------------------
local BulkSell = {}
CobysLootSweeper.BulkSell = BulkSell

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Utilities = CobysLootSweeper.Utilities

local WIDTH = 440   -- Customize's two columns fit their labels and counts (Verify q121-01)
local PAD = 12
local ROW = 20

local p = { qualityBoxes = {}, kindBoxes = {} }

local function Bulk() return CobysLootSweeper.Bulk end
local function Scope() return CobysLootSweeper.UI.RunFilter() end

local PRESET_ICONS = {
  junk = "Interface\\Icons\\INV_Misc_Coin_02", greens = "Interface\\Icons\\INV_Misc_Gem_Emerald_02",
  consumables = "Interface\\Icons\\INV_Potion_51", materials = "Interface\\Icons\\INV_Ore_Copper_01",
  post = "Interface\\Icons\\INV_Misc_Note_02", everything = "Interface\\Icons\\INV_Misc_Bag_10",
}

local function Plural(n, one, many) return n == 1 and one or many end

local function CountText(c, copper)
  if c == 0 then return "none" end
  return string.format("%d %s · %s", c, Plural(c, "stack", "stacks"), Utilities.GoldShort(copper))
end

-- The short form beside a tick: "(2 · 70g)"
local function ShortCount(c, copper)
  if c == 0 then return "(none)" end
  return string.format("(%d · %s)", c, Utilities.GoldShort(copper))
end

-------------------------------------------------------------------------------
-- The plan for what is ticked now
-------------------------------------------------------------------------------
function BulkSell.CurrentPlan()
  local saved = Bulk().Saved()
  return Bulk().Plan(Scope(), Bulk().PickOf(saved), Bulk().AcceptOf(saved)), saved
end

-- The lines under the switches: what it sells, what it counted, what it left out
local LEFT_WORDS = {
  protected = "protected", gear = "held as possible upgrades", held = "held for a use", kept = "kept",
  novendor = "no vendor buys", warbound = "warbound", noprice = "with no recent AH price",
}
local LEFT_ORDER = { "protected", "gear", "held", "kept", "novendor", "warbound", "noprice" }

function BulkSell.Lines(plan)
  local first = string.format("%d %s · frees %d bag %s · %s", plan.stacks, Plural(plan.stacks, "stack", "stacks"),
    plan.stacks, Plural(plan.stacks, "slot", "slots"), Utilities.Money(plan.copper))
  local notes = {}
  local c = plan.counts
  if c.auction > 0 then notes[#notes + 1] = string.format("%d the AH values above vendor", c.auction) end
  if c.reagent > 0 then notes[#notes + 1] = string.format("%d crafting %s", c.reagent, Plural(c.reagent, "reagent", "reagents")) end
  local mine = 0
  for _, row in ipairs(plan.rows) do
    if row.facts.classID == CobysLootSweeper.Rules.CLASS_CONSUMABLE and row.facts.usable then mine = mine + 1 end
  end
  if mine > 0 then notes[#notes + 1] = string.format("%d %s you can use", mine, Plural(mine, "consumable", "consumables")) end
  if c.warbound > 0 then notes[#notes + 1] = string.format("%d warbound", c.warbound) end
  local left = {}
  for _, code in ipairs(LEFT_ORDER) do
    local n = plan.left[code]
    if n and n > 0 then left[#left + 1] = string.format("%d %s", n, LEFT_WORDS[code]) end
  end
  if plan.ignored > 0 then left[#left + 1] = string.format("%d ignored", plan.ignored) end
  return first, table.concat(notes, " · "), #left > 0 and ("Left out: " .. table.concat(left, ", ")) or "Nothing left out"
end

-------------------------------------------------------------------------------
-- Selling
-------------------------------------------------------------------------------
local function Start(rows, accept)
  if Utilities.Guarded("bulk sell") then return false end
  local ok = CobysLootSweeper.Seller.Start(rows, { accept = accept })
  if ok then
    BulkSell.Close()
  else
    Utilities.Message("Bulk sell didn't start: the vendor closed, you're in combat, or a sale is already running.")
  end
  return ok
end

local function DialogBody(plan)
  local _, notes, left = BulkSell.Lines(plan)
  local lines = { "Loot Sweeper sells exactly the stacks the list shows, cheapest first, and checks each one again before it sells." }
  if notes ~= "" then lines[#lines + 1] = notes .. "." end
  lines[#lines + 1] = left .. "."
  lines[#lines + 1] = "The vendor's buyback keeps only your last 12 sales."
  return table.concat(lines, "\n")
end

local function BuildDialog()
  p.dialog = UI.CreateDialogPopup({
    title = "Bulk sell", icon = CobysLootSweeper.ICON, hidden = true, width = 400,
    confirmText = "Sell", cancelText = "Cancel",
    onConfirm = function()
      local pending = p.pending
      p.pending = nil
      if pending then Start(pending.rows, pending.accept) end
    end,
  })
end

-- The question before a bulk sale: the reviewed rows, frozen now (anything
-- that changes is skipped by the seller's checks), wait in p.pending
local function ShowConfirm(plan, accept)
  p.pending = { rows = plan.rows, accept = accept }
  p.dialog.Title:SetText(string.format("Sell %d %s for %s?", plan.stacks, Plural(plan.stacks, "stack", "stacks"),
    Utilities.Money(plan.copper)))
  p.dialog:SetBody(DialogBody(plan))
  p.dialog.ConfirmButton:SetText(string.format("Sell %d", plan.stacks))
  p.dialog:Show()
end

function BulkSell.Sell()
  if Utilities.Guarded("bulk sell") then return false end
  if InCombatLockdown() or not p.dialog then return false end
  local plan, saved = BulkSell.CurrentPlan()
  if plan.stacks == 0 or not CobysLootSweeper.Seller.MerchantReady() then return false end
  local accept = Bulk().AcceptOf(saved)
  if CobysLootSweeper.Config.Get("bulkConfirm") == false then return Start(plan.rows, accept) end
  ShowConfirm(plan, accept)
  return true
end

function BulkSell.DropConfirm()
  p.pending = nil
  if p.dialog and p.dialog:IsShown() then p.dialog:Hide() end
end

-------------------------------------------------------------------------------
-- The panel
-------------------------------------------------------------------------------
-- The pick changed: a question asked about the old pick is dropped
local function Changed()
  BulkSell.DropConfirm()
  BulkSell.Refresh()
end

local function PresetTiles()
  local tiles = {}
  for _, preset in ipairs(Bulk().PRESETS) do
    tiles[#tiles + 1] = {
      key = preset.key, icon = PRESET_ICONS[preset.key], value = preset.label,
      label = function(ctx) local c = ctx.presets[preset.key] return CountText(c.stacks, c.copper) end,
      labelShort = function(ctx) return tostring(ctx.presets[preset.key].stacks) end,
      dim = function(ctx) return ctx.presets[preset.key].stacks == 0 end,
    }
  end
  return tiles
end

local function Box(parent, onChange)
  local box = UI.CreateCheckbox(parent, { label = " ", onChange = onChange })
  box:SetHeight(ROW)
  return box
end

local function Build()
  local main = _G.CobysLootSweeperWindow
  local f = UI.CreateWindow({
    name = "CobysLootSweeperBulkSell", title = "Bulk sell", icon = CobysLootSweeper.ICON,
    width = WIDTH, height = 520, escapeCloses = true,
    point = { "TOPLEFT", main or UIParent, main and "TOPRIGHT" or "CENTER", 4, 0 },
  })
  p.frame = f
  p.ctx = { presets = {} }
  p.scope = f:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  p.scope:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -30)
  p.scope:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  p.scope:SetJustifyH("LEFT")
  p.tiles = UI.CreateStatTiles(f, {
    tiles = PresetTiles(), columns = 2, minTileWidth = 140, height = 46, context = p.ctx,
    selected = function() local s = Bulk().Saved() return not s.custom and s.preset or nil end,
    onClick = function(key)
      local s = Bulk().Saved()
      s.preset, s.custom = key, false
      Changed()
    end,
    onHeight = function() BulkSell.Layout() end,
  })
  p.tiles:SetPoint("TOPLEFT", p.scope, "BOTTOMLEFT", 0, -6)
  p.tiles:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  p.custom = UI.CreateCheckbox(f, { label = "Customize: pick qualities and kinds", onChange = function(on)
    local s = Bulk().Saved()
    s.custom = on == true
    Changed()
  end })
  p.qualityHead = f:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  p.qualityHead:SetText("Quality")
  p.kindHead = f:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  p.kindHead:SetText("Kind")
  for i, q in ipairs(Bulk().QUALITIES) do
    p.qualityBoxes[i] = Box(f, function(on)
      Bulk().Saved().quality[q.key] = on and true or nil
      Changed()
    end)
    p.qualityBoxes[i].key = q.key
  end
  p.warbound = UI.CreateCheckbox(f, { label = " ", onChange = function(on)
    Bulk().Saved().warbound = on == true
    Changed()
  end })
  p.noPrice = UI.CreateCheckbox(f, { label = " ", onChange = function(on)
    Bulk().Saved().noPrice = on == true
    Changed()
  end })
  p.summary = f:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  p.notes = f:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  p.left = f:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  for _, fs in ipairs({ p.summary, p.notes, p.left }) do
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
  end
  local gray = U.Colors.LABEL_GRAY
  p.left:SetTextColor(gray[1], gray[2], gray[3])
  p.sell = UI.CreateButton(f, { text = "Sell", size = { 200, 26 }, onClick = function() BulkSell.Sell() end })
  p.close = UI.CreateButton(f, { text = "Close", size = { 90, 26 }, onClick = function() BulkSell.Close() end })
  f:HookScript("OnHide", function()
    BulkSell.DropConfirm()
    CobysLootSweeper.UI.SetPlanRows(nil)
  end)
  BuildDialog()
  -- The panel describes the main window's list: it goes when the list does
  if main then main:HookScript("OnHide", function() BulkSell.Close() end) end
end

-- One kind's tick, made the first time that kind shows (never in combat:
-- Open refuses there)
local function KindBox(i)
  if not p.kindBoxes[i] then
    if InCombatLockdown() then return nil end
    local box
    box = Box(p.frame, function(on)
      Bulk().Saved().kind[box.key] = on and true or nil
      Changed()
    end)
    p.kindBoxes[i] = box
  end
  return p.kindBoxes[i]
end

local function Place(region, y, x, width)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", p.frame, "TOPLEFT", x or PAD, y)
  if width then region:SetWidth(width) end
end

-- Stacks the panel's parts from the top; the window takes their height
function BulkSell.Layout()
  local f = p.frame
  if not f then return end
  local y = -30 - 16 - 6 - (p.tiles:GetHeight() or 0) - 10
  Place(p.custom, y)
  y = y - ROW - 6
  local s = Bulk().Saved()
  local half = (WIDTH - PAD * 3) / 2
  p.qualityHead:SetShown(s.custom == true)
  p.kindHead:SetShown(s.custom == true)
  if s.custom then
    Place(p.qualityHead, y)
    Place(p.kindHead, y, PAD * 2 + half)
    y = y - 18
    local rows = 0
    for i, box in ipairs(p.qualityBoxes) do Place(box, y - (i - 1) * ROW) rows = i end
    local shownKinds = 0
    for _, box in ipairs(p.kindBoxes) do
      if box:IsShown() then
        Place(box, y - shownKinds * ROW, PAD * 2 + half)
        shownKinds = shownKinds + 1
      end
    end
    y = y - math.max(rows, shownKinds) * ROW - 8
  end
  Place(p.warbound, y)
  Place(p.noPrice, y - ROW)
  y = y - ROW * 2 - 10
  for _, fs in ipairs({ p.summary, p.notes, p.left }) do
    Place(fs, y, PAD, WIDTH - PAD * 2)
    y = y - math.max(14, fs:GetStringHeight() or 14) - 4
  end
  y = y - 8
  p.sell:ClearAllPoints()
  p.sell:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
  p.close:ClearAllPoints()
  p.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
  f:SetHeight(-y + 26 + PAD)
end

function BulkSell.Refresh()
  if not (p.frame and p.frame:IsShown()) then return end
  local scope = Scope()
  local saved = Bulk().Saved()
  local accept = Bulk().AcceptOf(saved)
  for _, preset in ipairs(Bulk().PRESETS) do
    local plan = Bulk().Plan(scope, preset.pick, accept)
    p.ctx.presets[preset.key] = { stacks = plan.stacks, copper = plan.copper }
  end
  local run = scope and CobysLootSweeper.Runs.RunName(scope)
  p.scope:SetText(run and ("Loot from " .. run) or "Loot from all your runs")
  p.tiles:Refresh()
  p.custom:SetChecked(saved.custom == true)
  local options = Bulk().Options(scope, accept)
  for _, box in ipairs(p.qualityBoxes) do
    local o = options.quality[box.key]
    box:SetShown(saved.custom == true)
    box:SetChecked(saved.quality[box.key] == true)
    box.text:SetText(Bulk().QUALITIES[box.key + 1].label .. " " .. ShortCount(o.count, o.copper))
  end
  for _, box in ipairs(p.kindBoxes) do box:Hide() end
  for i, key in ipairs(options.kinds) do
    local o = options.kind[key]
    if o.count > 0 or saved.kind[key] or i <= #Bulk().KINDS then
      local box = KindBox(i)
      if not box then break end   -- a new kind waits for the end of combat
      box.key = key
      box:SetShown(saved.custom == true)
      box:SetChecked(saved.kind[key] == true)
      box.text:SetText(Bulk().KindLabel(key) .. " " .. ShortCount(o.count, o.copper))
    end
  end
  local plan = Bulk().Plan(scope, Bulk().PickOf(saved), accept)
  local wide = Bulk().Plan(scope, Bulk().PickOf(saved), { warbound = true, noPrice = true })
  p.warbound:SetChecked(saved.warbound == true)
  p.warbound.text:SetText(string.format("Include warbound items (%d)", wide.counts.warbound))
  p.noPrice:SetChecked(saved.noPrice == true)
  p.noPrice.text:SetText(string.format("Include items with no recent AH price (%d)", wide.counts.noPrice))
  local first, notes, left = BulkSell.Lines(plan)
  p.summary:SetText(first)
  p.notes:SetText(notes)
  p.left:SetText(left)
  local ready = CobysLootSweeper.Seller.MerchantReady() and not CobysLootSweeper.Seller.IsBusy()
  p.sell:SetText(plan.stacks > 0 and string.format("Sell %d %s for %s", plan.stacks,
    Plural(plan.stacks, "stack", "stacks"), Utilities.Money(plan.copper)) or "Nothing to sell")
  p.sell:SetEnabled(plan.stacks > 0 and ready)
  CobysLootSweeper.UI.SetPlanRows(plan.rows)
  BulkSell.Layout()
end

-- Open(presetKey): out of combat, beside the main window; a preset given
-- (the Post tab's "Vendor these instead...") is picked
function BulkSell.Open(presetKey)
  if InCombatLockdown() then
    Utilities.Message("Bulk sell opens out of combat.")
    return false
  end
  if not p.frame then Build() end
  if presetKey and Bulk().Preset(presetKey) then
    local s = Bulk().Saved()
    s.preset, s.custom = presetKey, false
  end
  local main = _G.CobysLootSweeperWindow
  if main then
    p.frame:ClearAllPoints()
    p.frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
  end
  p.frame:Show()
  BulkSell.Refresh()
  return true
end

function BulkSell.Close()
  if p.frame then p.frame:Hide() end
end

function BulkSell.IsOpen() return p.frame ~= nil and p.frame:IsShown() end

-- The main window's run picker moved: a new plan, and no confirmation for
-- the old one
function BulkSell.OnScopeChanged()
  BulkSell.DropConfirm()
  BulkSell.Refresh()
end

-- Tests and Verify: the panel's parts, and the question shown without the
-- scene guard's refusal (its Sell still refuses: Start is guarded)
BulkSell._test = {
  State = function() return p end,
  ShowConfirm = function()
    local plan, saved = BulkSell.CurrentPlan()
    ShowConfirm(plan, Bulk().AcceptOf(saved))
  end,
}

-- Anything that changes the pile, the vendor or the seller repaints it
local refresh = CobySuite_CobysLootSweeper.Utilities.Coalesce(0.2, function() BulkSell.Refresh() end)
local listener = {}
function listener:ReceiveEvent(_, kind, isOpen)
  if kind == "merchant" and isOpen == false then BulkSell.Close() return end
  refresh:Call()
end
CobysLootSweeper.EventBus:Register(listener, {
  CobysLootSweeper.Events.ViewUpdated, CobysLootSweeper.Events.SellChanged, CobysLootSweeper.Events.InteractionChanged,
})
