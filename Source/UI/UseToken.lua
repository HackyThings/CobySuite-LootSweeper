-------------------------------------------------------------------------------
-- UseToken: use a class token from a loot row's "Use token..." menu
--
-- Using an item is a protected action: addon code can't use one, and a menu
-- entry can't make the secure click itself. So the row menu's "Use token..."
-- opens this small window, whose Use button is an insecure action button
-- (type "item", the token's bag and slot): the player's own click on it uses
-- the token on the secure path, as Recollect's Show Achievement prompt runs
-- its macro. The click raises a fence first (Fences.Pulse), so nothing else
-- arriving then counts as loot, and tells Runs to expect the token's item
-- (Runs.ExpectConversion): the piece it gives joins the token's run, sorted
-- like any other loot.
--
-- Never a sale: with a vendor open, "using" a bag item sells it (the game
-- treats it like a right-click on the item), and no macro condition can tell
-- a vendor is open. So the button is armed (type "item") only while no vendor
-- is open and out of combat, and checked again right before every click
-- (PreClick): a vendor open then disarms it before the action runs. With a
-- vendor open the button reads "Close vendor" and closes it (HideUIPanel, the
-- panel manager's own path); the next click uses the token. Combat disarms it
-- as it starts (PLAYER_REGEN_DISABLED comes before the lockdown), since no
-- attribute can change in combat; it is armed again when combat ends.
-- (Sold from this window at Vaskarn in game, 2026-09-30.)
-------------------------------------------------------------------------------
local UseToken = {}
CobysLootSweeper.UseToken = UseToken

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI

local WIDTH, HEIGHT, PAD = 380, 180, 16

local seams = {
  InCombat = function() return InCombatLockdown() end,
  Message = function(text) CobysLootSweeper.Utilities.Message(text) end,
  Locate = function(guid) return CobysLootSweeper.Bags.Locate(guid) end,
  -- A vendor counts as open while its window shows or the game's merchant
  -- interaction is up (either one is enough to sell)
  MerchantOpen = function()
    local frame = _G.MerchantFrame
    return (frame ~= nil and frame:IsShown()) or CobysLootSweeper.Fences.IsMerchantOpen()
  end,
  CloseMerchant = function()
    if _G.MerchantFrame then HideUIPanel(_G.MerchantFrame) end
  end,
}
UseToken._test = { seams = seams }

local dialog
local pending   -- { guid, link, name, icon }

UseToken.BODY = "Use it to get your class's piece. The piece joins this token's run and is sorted like the rest of its loot."
UseToken.VENDOR_BODY = "A vendor window is open, and using an item there sells it. Close the vendor first, then press Use."
UseToken.GONE_BODY = "That token isn't in your bags any more."
UseToken.COMBAT_BODY = "Tokens can't be used from Loot Sweeper in combat. Try again once combat ends."

-- The button does nothing: no action until it is aimed again
local function Disarm()
  dialog.Use:SetAttribute("type", nil)
  dialog.Use:SetAttribute("item", nil)
end

-- Aims the Use button: armed at the token's bag slot only with no vendor
-- open and out of combat. Returns "armed", "vendor", "combat", "gone" or "guarded"
function UseToken.Aim()
  if not dialog or not pending then return "gone" end
  if seams.InCombat() then
    -- Attributes can't change now; combat's start already disarmed it
    dialog.Body:SetText(UseToken.COMBAT_BODY)
    dialog.Use:Disable()
    dialog.mode = "combat"
    return "combat"
  end
  -- A development scene's sample panel: never aimed at anything
  if CobysLootSweeper.SceneGuard then
    Disarm()
    dialog.Use:SetText("Use")
    dialog.Use:Disable()
    dialog.Body:SetText(UseToken.BODY)
    dialog.mode = "guarded"
    return "guarded"
  end
  local bag, slot = seams.Locate(pending.guid)
  if not bag then
    Disarm()
    dialog.Use:SetText("Use")
    dialog.Use:Disable()
    dialog.Body:SetText(UseToken.GONE_BODY)
    dialog.mode = "gone"
    return "gone"
  end
  if seams.MerchantOpen() then
    Disarm()
    dialog.Use:SetText("Close vendor")
    dialog.Use:Enable()
    dialog.Body:SetText(UseToken.VENDOR_BODY)
    dialog.mode = "vendor"
    return "vendor"
  end
  dialog.Use:SetAttribute("type", "item")
  dialog.Use:SetAttribute("item", bag .. " " .. slot)
  dialog.Use:SetText("Use")
  dialog.Use:Enable()
  dialog.Body:SetText(UseToken.BODY)
  dialog.mode = "armed"
  return "armed"
end

-- Right before the secure action: aim again (a vendor opened since the last
-- aim disarms it now), and fence what the token creates
function UseToken.PreClick()
  if seams.InCombat() then return end
  if UseToken.Aim() == "armed" then
    CobysLootSweeper.Fences.Pulse()
    CobysLootSweeper.Runs.ExpectConversion(pending.guid)
  end
end

-- After the click: a disarmed "Close vendor" press closes the vendor
function UseToken.PostClick()
  if not dialog then return end
  if dialog.mode == "vendor" then
    pcall(seams.CloseMerchant)
    UseToken.Aim()
    return
  end
  if dialog.mode == "armed" then dialog:Hide() end
end

local function Build()
  if dialog or seams.InCombat() then return end
  dialog = UI.CreateWindow({
    name = "CobysLootSweeperUseToken", title = U.WrapColor(CobysLootSweeper.BRAND_COLOR, "Coby's Loot Sweeper"), icon = CobysLootSweeper.ICON,
    width = WIDTH, height = HEIGHT, strata = "DIALOG", escapeCloses = true,
    point = { "CENTER", UIParent, "CENTER", 0, 120 },
  })
  dialog.Icon = dialog:CreateTexture(nil, "ARTWORK")
  dialog.Icon:SetSize(40, 40)
  dialog.Icon:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -36)
  dialog.Name = dialog:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  dialog.Name:SetPoint("TOPLEFT", dialog.Icon, "TOPRIGHT", 10, -2)
  dialog.Name:SetPoint("RIGHT", dialog, "RIGHT", -PAD, 0)
  dialog.Name:SetJustifyH("LEFT")
  -- Hovering the icon or the name shows the token (Task #235)
  dialog.Hover = CreateFrame("Frame", nil, dialog)
  dialog.Hover:SetPoint("TOPLEFT", dialog.Icon, "TOPLEFT")
  dialog.Hover:SetPoint("BOTTOMLEFT", dialog.Icon, "BOTTOMLEFT")
  dialog.Hover:SetPoint("RIGHT", dialog, "RIGHT", -PAD, 0)
  dialog.Hover:EnableMouse(true)
  UI.AddItemTooltip(dialog.Hover, function() return pending and pending.link or nil end, "ANCHOR_RIGHT")
  dialog.Body = dialog:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  dialog.Body:SetPoint("TOPLEFT", dialog.Icon, "BOTTOMLEFT", 0, -10)
  dialog.Body:SetPoint("RIGHT", dialog, "RIGHT", -PAD, 0)
  dialog.Body:SetJustifyH("LEFT")
  dialog.Body:SetWordWrap(true)
  -- The shared button's look on an insecure action button: one plain click,
  -- on release, uses the item it is aimed at (when armed)
  dialog.Use = UI.CreateButton(dialog, { text = "Use", size = { 130, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMLEFT", dialog, "BOTTOMLEFT", PAD, 14 }, template = "UIPanelButtonTemplate, InsecureActionButtonTemplate" })
  UI.ConfigureSecureClicker(dialog.Use, { blockModified = true })
  dialog.Use:SetScript("PreClick", function() UseToken.PreClick() end)
  dialog.Use:HookScript("PostClick", function()
    if seams.InCombat() then
      seams.Message(UseToken.COMBAT_BODY)
      return
    end
    UseToken.PostClick()
  end)
  dialog.Cancel = UI.CreateButton(dialog, { text = "Cancel", size = { 110, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -PAD, 14 },
    onClick = function() dialog:Hide() end })
  dialog:HookScript("OnHide", function()
    pending = nil
    if not seams.InCombat() then Disarm() end
  end)
  dialog:Hide()
  UseToken.dialog = dialog
end

-- Open(row): the window for one token row (a grouped row uses its first copy)
function UseToken.Open(row)
  if seams.InCombat() then
    seams.Message(UseToken.COMBAT_BODY)
    return false
  end
  Build()
  if not dialog then return false end
  local first = row.copies and row.copies[1] or row
  pending = { guid = first.guid, link = first.facts.link, name = first.facts.name, icon = first.facts.icon }
  dialog.Icon:SetTexture(pending.icon or 134400)
  dialog.Name:SetText(pending.link or pending.name or "Token")
  local state = UseToken.Aim()
  dialog:Show()
  return state == "armed"
end

-- A vendor opening or closing re-aims it; combat's start disarms it while
-- attributes can still change, and its end aims it again
local listener = {}
function listener:ReceiveEvent(_, kind)
  if kind == "merchant" and dialog and dialog:IsShown() and pending then UseToken.Aim() end
end
CobysLootSweeper.EventBus:Register(listener, { CobysLootSweeper.Events.InteractionChanged })

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
  if not dialog then return end
  if event == "PLAYER_REGEN_DISABLED" then
    Disarm()
    dialog.mode = "combat"
  elseif dialog:IsShown() and pending then
    UseToken.Aim()
  end
end)
UseToken._test.OnCombat = function(event) combat:GetScript("OnEvent")(combat, event) end

EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", Build)
