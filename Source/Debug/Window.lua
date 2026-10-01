-------------------------------------------------------------------------------
-- CobysLootSweeper Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

CobysLootSweeper.DebugWindow = CobySuite_CobysLootSweeper.Debug.NewWindow({
  windowName = "CobysLootSweeperDebugWindow",
  title = "Coby's Loot Sweeper Debug Log",
  logger = CobysLootSweeper.Debug,
})
