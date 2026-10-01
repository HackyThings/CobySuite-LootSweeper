-------------------------------------------------------------------------------
-- CobysLootSweeper Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow),
-- as Recollect's: a sidebar of categories (Windows, Selling, Prices), a
-- Guide button beside Defaults, staged edits that Apply writes through Config.Set,
-- Cancel, and Defaults. Built at load, so opening it never creates frames in
-- combat; the controls are painted from config on every show, and a
-- ConfigChanged event repaints an open window. The addon is also listed
-- under Options > AddOns with a button that opens this window
-- (CobySuite.UI.RegisterSettingsCategory).
-------------------------------------------------------------------------------

local Config = CobysLootSweeper.Config
local Opt = Config.Options
local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI

local WINDOW_W = 560
local WINDOW_H = 420

local window = UI.CreateSettingsWindow({
  name    = "CobysLootSweeperOptionsWindow",
  title   = U.WrapColor(CobysLootSweeper.BRAND_COLOR, "Coby's Loot Sweeper") .. " Settings",
  icon    = CobysLootSweeper.ICON,
  config  = Config,
  width   = WINDOW_W,
  height  = WINDOW_H,
  persist = {
    svTable = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end,
    key = "options",
  },
  watch   = { bus = CobysLootSweeper.EventBus, event = CobysLootSweeper.Events.ConfigChanged },
  message = function(text) CobysLootSweeper.Utilities.Message(text) end,
  footerButtons = {
    {
      text = "Guide", width = 80,
      tooltip = "Open the feature guide: how runs, selling and posting work.",
      onClick = function() if CobysLootSweeper.Guide then CobysLootSweeper.Guide.Toggle() end end,
    },
  },
  categories = {
    {
      key = "windows", label = "Windows",
      build = function(panel)
        panel:Section("Where the window opens")
        panel:Checkbox{
          key = Opt.SHOW_AT_MERCHANT, label = "Loot Sweeper button on vendors",
          tooltip = "A Loot Sweeper button on the vendor window. It shimmers when a run left loot you haven't looked at; click it to open the window beside the vendor.",
        }
        panel:Checkbox{
          key = Opt.SHOW_AT_AUCTION_HOUSE, label = "Open beside the auction house",
          tooltip = "Open the window on the Post tab at the auction house when items are worth posting.",
        }
        panel:Section("Messages")
        panel:Checkbox{
          key = Opt.ANNOUNCE, label = "Say when a run starts and ends",
          tooltip = "A line in chat when tracking starts, and a summary of what is waiting when it ends.",
        }
      end,
    },
    {
      key = "selling", label = "Selling",
      build = function(panel)
        panel:Section("At the vendor")
        panel:Checkbox{
          key = Opt.STOP_AFTER_12, label = "Pause after every 12 sales",
          tooltip = "The vendor's buyback holds the last 12 sales. On: selling pauses after each 12 so you can look before carrying on.",
        }
        panel:Checkbox{
          key = Opt.KEEP_UPGRADES, label = "Never sell possible upgrades",
          tooltip = "Gear with a higher item level than what you wear on average stays in Keep. Off: it is sorted like any other gear.",
        }
        panel:Checkbox{
          key = Opt.SKIP_TRADE_QUESTION, label = "Sell loot you could still trade without asking",
          tooltip = "Loot from a group can be traded to its members for two hours, and the game asks before you sell it. On: Loot Sweeper answers yes for the items it sells, nothing else.",
        }
      end,
    },
    {
      key = "prices", label = "Prices",
      build = function(panel)
        panel:Section("Worth posting")
        panel:Input{
          key = Opt.POST_MIN_GOLD, label = "Minimum auction gain (gold)", numeric = true, digits = true,
          width = 80,
          tooltip = "A stack goes to Post when its AH estimate, after the 5% cut, is at least twice its vendor price and at least this many gold more.",
        }
        panel:Slider{
          key = Opt.MAX_PRICE_AGE_DAYS, label = "Maximum price age (days)", min = 0, max = 21, step = 1,
          tooltip = "Loot Sweeper sells a tradeable item (other than junk) by itself only when Auctionator saw an exact price for it this recently. Without one, the item stays in Keep.",
        }
      end,
    },
  },
})

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  window:Toggle()
end

function Config.OpenSettings()
  window:Open()
end

-------------------------------------------------------------------------------
-- Options > AddOns entry (registered once this addon has finished loading)
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", function()
  UI.RegisterSettingsCategory({
    name        = "Coby's Loot Sweeper",
    brandColor  = CobysLootSweeper.BRAND_COLOR,
    version     = CobysLootSweeper.VERSION,
    description = {
      "Sell or post only the loot from your last old-raid or dungeon run. Everything you already had stays safe.",
      "The settings live in the addon's own settings window.",
    },
    slash       = "/ls settings",
    onOpen      = Config.OpenSettings,
  })
end)
