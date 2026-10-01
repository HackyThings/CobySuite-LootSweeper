-------------------------------------------------------------------------------
-- CobysLootSweeper Debug Logger: thin wrapper around CobySuite.Debug.NewLogger
-------------------------------------------------------------------------------

CobysLootSweeper.Debug = CobySuite_CobysLootSweeper.Debug.NewLogger({
  addonName = "CobysLootSweeper",
  categories = {
    "INIT", "CONFIG", "RUN", "TRACK", "SELL", "UI", "DIAG",
  },
  savedVariable = "COBYS_LOOT_SWEEPER_DEBUG_LOG",
  sessionHeader = function(lines)
    CobySuite_CobysLootSweeper.Debug.AppendConfigSnapshot(lines, "COBYS_LOOT_SWEEPER_CONFIG")
  end,
})
