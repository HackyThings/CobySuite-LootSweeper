-------------------------------------------------------------------------------
-- Launcher: the addon compartment entry (left-click the window,
-- right-click settings); no minimap button
-------------------------------------------------------------------------------
local launcher = CobySuite_CobysLootSweeper.UI.CreateLauncher({
  name = "CobysLootSweeper",
  label = "Coby's Loot Sweeper",
  icon = CobysLootSweeper.ICON,
  minimapButton = false,
  broker = false,
  tooltip = function()
    local s = CobysLootSweeper.Pile.Summary()
    local run = CobysLootSweeper.Runs.Active()
    local status = {}
    if run then status[#status + 1] = "Tracking " .. (run.name or "a run") end
    status[#status + 1] = string.format("To sell: %d (%s)", s.vendor.count, CobysLootSweeper.Utilities.Money(s.vendor.value))
    status[#status + 1] = string.format("Worth posting: %d", s.post.count)
    status[#status + 1] = string.format("Protected: %d", s.keep.count)
    return CobySuite_CobysLootSweeper.UI.LauncherTooltip({
      title = "Coby's Loot Sweeper", brandColor = CobysLootSweeper.BRAND_COLOR, icon = CobysLootSweeper.ICON,
      status = status, leftClick = "Open Loot Sweeper", rightClick = "Open settings",
    })
  end,
  onLeftClick = function() CobysLootSweeper.UI.Toggle() end,
  onRightClick = function() CobysLootSweeper.Config.ToggleSettings() end,
})

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function() launcher:Initialize() end)

function CobysLootSweeper_OnAddonCompartmentClick(_, button) launcher:OnCompartmentClick(button) end
function CobysLootSweeper_OnAddonCompartmentEnter(_, menuItem) launcher:OnCompartmentEnter(menuItem) end
function CobysLootSweeper_OnAddonCompartmentLeave() launcher:OnCompartmentLeave() end
