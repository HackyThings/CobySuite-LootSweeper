CobysLootSweeper = {
  Debug = {},
  Config = {},
  Utilities = {},
  Data = {},
}

CobysLootSweeper.BRAND_COLOR = "E07A5F"
CobysLootSweeper.ICON = "Interface\\Icons\\INV_Misc_Bag_10"

-------------------------------------------------------------------------------
-- EventBus event constants
-------------------------------------------------------------------------------
CobysLootSweeper.Events = {
  ConfigChanged = "cobyslootsweeper_config_changed",           -- name, value, old
  PileChanged = "cobyslootsweeper_pile_changed",               -- the ledger's pile or a choice changed
  RunChanged = "cobyslootsweeper_run_changed",                 -- a run started, ended or is preparing
  ViewChanged = "cobyslootsweeper_view_changed",               -- Auctionator's prices changed
  ViewUpdated = "cobyslootsweeper_view_updated",               -- the pile view is stale; repaint
  SellChanged = "cobyslootsweeper_sell_changed",               -- the seller's progress
  InteractionChanged = "cobyslootsweeper_interaction_changed", -- kind ("merchant", "auction", "fence"), isOpen
  HistoryChanged = "cobyslootsweeper_history_changed",         -- a record or a total changed
}

-------------------------------------------------------------------------------
-- Addon metadata
-------------------------------------------------------------------------------
local ADDON_NAME = "CobysLootSweeper"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.1"
CobysLootSweeper.VERSION = VERSION

-------------------------------------------------------------------------------
-- Slash commands
--
-- Registered through CobySuite.Slash, which generates help and version.
-- Everything else loads after Core.lua, so each command resolves its module
-- per call.
-------------------------------------------------------------------------------
local function OpenWindow()
  if CobysLootSweeper.UI then CobysLootSweeper.UI.Toggle() end
end

-- "/ls addons" and the guide's last section: every addon by Cobanyte
-- (CobySuite.UI.ToggleAddonsWindow, the same list in each addon)
CobysLootSweeper.AddonsList = {
  host = "CobysLootSweeper", slash = "/ls", icon = CobysLootSweeper.ICON,
  message = function(text) CobysLootSweeper.Utilities.Message(text) end,
  state = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end,
}

-- "/ls reset windows" (CobySuite.UI.ResetWindows): every window saves into the window-state
-- table, so those are found by it; the debug window and the three panels built without a
-- saved place (Bulk sell, the one-at-a-time panel, Use token) are listed here
CobysLootSweeper.WindowsReset = {
  host = "CobysLootSweeper", title = "Coby's Loot Sweeper", icon = CobysLootSweeper.ICON,
  message = function(text) CobysLootSweeper.Utilities.Message(text) end,
  states = { function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end },
  windows = function()
    local ns, list = CobysLootSweeper, {}
    -- each one only once it exists: the panels are built the first time they open
    local function Add(frame) if frame then list[#list + 1] = frame end end
    Add(ns.DebugWindow)
    Add(ns.BulkSell and ns.BulkSell.Frame())
    Add(ns.StepPanel and ns.StepPanel.Frame())
    Add(ns.UseToken and ns.UseToken.Frame())
    return list
  end,
}

CobySuite_CobysLootSweeper.Slash.Register({
  key = "COBYSLOOTSWEEPER",
  -- /cobyslootsweep and /lootsweep stay from before the rename to Loot Sweeper
  slashes = { "/ls", "/sweep", "/lootsweeper", "/lootsweep", "/cobyslootsweeper", "/cobyslootsweep" },
  title = "Coby's Loot Sweeper",
  version = VERSION,
  message = function(text) CobysLootSweeper.Utilities.Message(text) end,
  onEmpty = OpenWindow,
  commands = CobySuite_CobysLootSweeper.Slash.StandardCommands({
    show = OpenWindow,
    addons = CobysLootSweeper.AddonsList,
    settings = function() CobysLootSweeper.Config.ToggleSettings() end,
    guide = function() CobysLootSweeper.Guide.Toggle() end,
    changelog = function() CobysLootSweeper.WhatsNew.Toggle() end,
    debug = function() CobysLootSweeper.DebugWindow:Toggle() end,
    resetWindows = CobysLootSweeper.WindowsReset,
    tests = function() return CobysLootSweeper.Tests end,
    extra = {
      { name = "start", help = "Start tracking a run here (old dungeons and raids start by themselves)",
        run = function() CobysLootSweeper.Runs.StartManual() end },
      { name = "stop", help = "Stop tracking the current run",
        run = function() CobysLootSweeper.Runs.Stop() end },
      { name = "forget", help = "Forget the remaining loot (the items stay in your bags)",
        run = function() CobysLootSweeper.UI.ConfirmForget() end },
      { name = "kept", help = "Open Your lists: kept items, remembered Sells and blocked places",
        run = function() CobysLootSweeper.Config.OpenSettings("lists") end },
      { name = "block", help = "Never track where you stand (undo it in /ls kept)",
        run = function() CobysLootSweeper.Runs.BlockHere() end },
    },
  }),
})

-------------------------------------------------------------------------------
-- Startup sequence
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
  if CobysLootSweeper.Config.InitializeData then
    CobysLootSweeper.Config.InitializeData()
  end
  CobysLootSweeper.Prefs.InitializeData()
  CobysLootSweeper.Runs.InitializeData()
  CobysLootSweeper.Prices.Hook()
  CobysLootSweeper.Debug.Log("INIT", "Coby's Loot Sweeper v%s loaded", VERSION)
end)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  -- A fresh install opens the guide; an update, the changelog
  if CobysLootSweeper.WhatsNew then CobysLootSweeper.WhatsNew.OnLogin() end
  -- The suite's version check: a chat line when a newer release is out
  CobySuite_CobysLootSweeper.VersionCheck.Register({
    key = "LS", addon = ADDON_NAME, title = "Coby's Loot Sweeper", color = CobysLootSweeper.BRAND_COLOR,
    enabled = function() return CobysLootSweeper.Config.Get(CobysLootSweeper.Config.Options.VERSION_CHECK) end,
    log = function(fmt, ...) CobysLootSweeper.Debug.Log("INIT", fmt, ...) end,
  })
  CobysLootSweeper.Debug.Log("INIT", "PLAYER_LOGIN complete")
end)
