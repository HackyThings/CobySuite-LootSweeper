-------------------------------------------------------------------------------
-- VendorButton: Loot Sweeper's button on the vendor window
--
-- While a vendor is open and run loot waits (setting showAtMerchant), a
-- square button with the addon's icon hangs off the vendor window's right
-- edge, like a side tab. Marching ants (the game's own autocast border)
-- run around it while some of that loot is new since the Loot Sweeper window
-- was last open. A click opens the window beside the vendor; the tooltip
-- says what is waiting. Only our own frame is anchored to the vendor
-- window; nothing of Blizzard's is changed.
-------------------------------------------------------------------------------
local VendorButton = {}
CobysLootSweeper.VendorButton = VendorButton

local Utilities = CobysLootSweeper.Utilities
local Events = CobysLootSweeper.Events

local SIZE = 36

local button

local function Merchant() return _G.MerchantFrame end

-- Loot that joined the pile after the window was last open
function VendorButton.HasNew()
  local seen = CobysLootSweeper.Runs.Char().reviewedAt or 0
  for _, row in ipairs(CobysLootSweeper.Pile.Rows()) do
    if (row.entry.at or 0) > seen then return true end
  end
  return false
end

-- The window was open: what is in it now has been seen
function VendorButton.MarkSeen()
  CobysLootSweeper.Runs.Char().reviewedAt = time()
  VendorButton.Refresh()
end

local function Tooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip_SetTitle(GameTooltip, "Coby's Loot Sweeper")
  local s = CobysLootSweeper.Pile.Summary()
  if s.vendor.count > 0 then
    GameTooltip_AddNormalLine(GameTooltip, string.format("%d %s to sell for %s.", s.vendor.count,
      s.vendor.count == 1 and "item" or "items", Utilities.Money(s.vendor.value)))
  end
  if s.post.count > 0 then
    GameTooltip_AddNormalLine(GameTooltip, string.format("%d worth checking on the auction house.", s.post.count))
  end
  if VendorButton.HasNew() then GameTooltip_AddHighlightLine(GameTooltip, "New loot since you last looked.") end
  GameTooltip_AddInstructionLine(GameTooltip, "Click to open Loot Sweeper beside the vendor.")
  GameTooltip:Show()
end

local function Build()
  if button then return end
  button = CreateFrame("Button", "CobysLootSweeperVendorButton", UIParent)
  button:SetSize(SIZE, SIZE)
  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetAllPoints()
  button.Icon:SetTexture(CobysLootSweeper.ICON)
  button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  button.Border = button:CreateTexture(nil, "OVERLAY")
  button.Border:SetPoint("TOPLEFT", -2, 2)
  button.Border:SetPoint("BOTTOMRIGHT", 2, -2)
  button.Border:SetAtlas("UI-HUD-ActionBar-IconFrame")
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  button.Ants = CreateFrame("Frame", nil, button, "AutoCastOverlayTemplate")
  button.Ants:ClearAllPoints()
  button.Ants:SetPoint("TOPLEFT", -1, 1)
  button.Ants:SetPoint("BOTTOMRIGHT", 1, -1)
  button:SetScript("OnEnter", Tooltip)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    local merchant = Merchant()
    if not merchant then return end
    CobysLootSweeper.UI.OpenDocked(merchant, "vendor")
  end)
  button:Hide()
end

-- Shown with the vendor while loot waits; ants while some of it is new
function VendorButton.Refresh()
  if not button then return end
  local merchant = Merchant()
  local open = merchant and merchant:IsShown() and CobysLootSweeper.Fences.IsMerchantOpen()
  local s = open and CobysLootSweeper.Config.Get("showAtMerchant") and CobysLootSweeper.Pile.Summary()
  local waiting = s and (s.vendor.count + s.post.count + s.keep.count) > 0
  if not waiting then
    button.Ants:ShowAutoCastEnabled(false)
    button:Hide()
    return
  end
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", merchant, "TOPRIGHT", 2, -64)
  button:SetFrameStrata(merchant:GetFrameStrata())
  button:SetFrameLevel(merchant:GetFrameLevel() + 20)
  button:Show()
  button.Ants:ShowAutoCastEnabled(VendorButton.HasNew() and not CobysLootSweeper.UI.IsShown())
end

local refresh = CobySuite_CobysLootSweeper.Utilities.Coalesce(0.2, function() VendorButton.Refresh() end)
local listener = {}
function listener:ReceiveEvent() refresh:Call() end
CobysLootSweeper.EventBus:Register(listener, { Events.InteractionChanged, Events.ViewUpdated, Events.ConfigChanged })

EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", Build)
