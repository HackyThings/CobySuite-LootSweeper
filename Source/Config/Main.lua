local Config = CobysLootSweeper.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New
---------------------------------------------------------------------------
local base = CobySuite_CobysLootSweeper.Config.New({
  savedVariable = "COBYS_LOOT_SWEEPER_CONFIG",
  options = {
    SHOW_AT_MERCHANT = "showAtMerchant",           -- the Loot Sweeper button on the vendor window
    SHOW_AT_AUCTION_HOUSE = "showAtAuctionHouse",  -- open it beside the auction house when items are worth posting
    ANNOUNCE = "announce",                         -- a chat line when a run starts and ends
    STOP_AFTER_12 = "stopAfter12",                 -- pause selling after every 12 sales
    KEEP_UPGRADES = "keepUpgrades",                -- keep gear above the equipped average item level in Keep (a Sell choice moves it)
    SKIP_TRADE_QUESTION = "skipTradeQuestion",     -- answer the game's "you could still trade this" for our sales
    POST_MIN_GOLD = "postMinGold",                 -- Post when the AH estimate is at least this much more (gold)
    MAX_PRICE_AGE_DAYS = "maxPriceAgeDays",        -- trust an Auctionator price seen within this many days
  },
  defaults = {
    ["showAtMerchant"] = true,
    ["showAtAuctionHouse"] = true,
    ["announce"] = true,
    ["stopAfter12"] = false,
    ["keepUpgrades"] = true,
    ["skipTradeQuestion"] = true,
    ["postMinGold"] = 50,
    ["maxPriceAgeDays"] = 3,
  },
  -- Set refuses a failing value and InitializeData puts the default back for
  -- a failing saved one (a hand-edited or damaged file)
  validate = {
    ["showAtMerchant"] = { type = "boolean" },
    ["showAtAuctionHouse"] = { type = "boolean" },
    ["announce"] = { type = "boolean" },
    ["stopAfter12"] = { type = "boolean" },
    ["keepUpgrades"] = { type = "boolean" },
    ["skipTradeQuestion"] = { type = "boolean" },
    ["postMinGold"] = { type = "number", min = 0, max = 1000000, integer = true },
    ["maxPriceAgeDays"] = { type = "number", min = 0, max = 21, integer = true },
  },
  debug = CobysLootSweeper.Debug,
  onSet = function(name, old, value)
    CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.ConfigChanged, name, value, old)
  end,
  onReset = function()
    CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.ConfigChanged)
  end,
})

-- Install onto CobysLootSweeper.Config namespace
Config.Options       = base.Options
Config.Defaults      = base.Defaults
Config.IsValidOption = base.IsValidOption
Config.CheckValue    = base.CheckValue
Config.Get           = base.Get
Config.Set           = base.Set
Config.Reset         = base.Reset

---------------------------------------------------------------------------
-- InitializeData: wraps base with addon-specific SavedVariable init
---------------------------------------------------------------------------
function Config.InitializeData()
  base.InitializeData()

  if type(COBYS_LOOT_SWEEPER_WINDOW_STATE) ~= "table" then
    COBYS_LOOT_SWEEPER_WINDOW_STATE = {}
  end

  CobysLootSweeper.Debug.Log("CONFIG", "Config initialized")
end
