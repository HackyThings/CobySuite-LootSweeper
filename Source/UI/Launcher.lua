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
    return {
      brandColor = CobysLootSweeper.BRAND_COLOR,
      title = "Coby's Loot Sweeper",
      subtitle = run and ("Tracking " .. (run.name or "a run")) or nil,
      body = {
        string.format("To sell: %d (%s)", s.vendor.count, CobysLootSweeper.Utilities.Money(s.vendor.value)),
        string.format("Worth posting: %d", s.post.count),
        string.format("Kept: %d", s.keep.count),
      },
      keys = {
        { key = "Left-click", desc = "Open the window" },
        { key = "Right-click", desc = "Open settings" },
      },
    }
  end,
  onLeftClick = function() CobysLootSweeper.UI.Toggle() end,
  onRightClick = function() CobysLootSweeper.Config.ToggleSettings() end,
})

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function() launcher:Initialize() end)

function CobysLootSweeper_OnAddonCompartmentClick(_, button) launcher:OnCompartmentClick(button) end
function CobysLootSweeper_OnAddonCompartmentEnter(_, menuItem) launcher:OnCompartmentEnter(menuItem) end
function CobysLootSweeper_OnAddonCompartmentLeave() launcher:OnCompartmentLeave() end
