-------------------------------------------------------------------------------
-- WhatsNew: the changelog window and what its login shows, on the shared
-- CobySuite.UI.CreateWhatsNewWindow (the suite's standard, as Recollect's):
-- one collapsible section per version of Data/Changelog.lua, /ls changelog
-- any time. At login COBYS_LOOT_SWEEPER_WINDOW_STATE.lastVersion says what the
-- player last ran: none (a fresh install) opens the feature guide, an older
-- version this window with every version since then open, else nothing;
-- either waits for combat to end. Core.lua's PLAYER_LOGIN calls OnLogin.
-------------------------------------------------------------------------------
local U = CobySuite_CobysLootSweeper.Utilities

local WhatsNew = {}
CobysLootSweeper.WhatsNew = WhatsNew

local changelog = CobySuite_CobysLootSweeper.UI.CreateWhatsNewWindow({
  name = "CobysLootSweeperChangelogWindow",
  title = U.WrapColor(CobysLootSweeper.BRAND_COLOR, "Coby's Loot Sweeper") .. ": What's New",
  icon = CobysLootSweeper.ICON,
  intro = "What changed in each version of Coby's Loot Sweeper, newest first. Click a version to open or close it.",
  footer = "Open this window any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ls changelog"),
  entries = CobysLootSweeper.Data.Changelog,
  version = CobysLootSweeper.VERSION,
  state = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end,
  onFirstRun = function() if CobysLootSweeper.Guide then CobysLootSweeper.Guide.Show() end end,
  combatMessage = function(text) CobysLootSweeper.Utilities.Message(text) end,
  onShow = function(what) CobysLootSweeper.Debug.Log("UI", "Login shows the %s", what) end,
})

function WhatsNew.Toggle() changelog:Toggle() end
function WhatsNew.OnLogin() changelog:OnLogin() end
