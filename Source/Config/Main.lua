local Config = CobysLootSweeper.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New
---------------------------------------------------------------------------
local base = CobySuite_CobysLootSweeper.Config.New({
  savedVariable = "COBYS_LOOT_SWEEPER_CONFIG",
  options = {
    SHOW_AT_MERCHANT = "showAtMerchant",           -- the Loot Sweeper button on the vendor window
    SHOW_AT_AUCTION_HOUSE = "showAtAuctionHouse",  -- open it beside the auction house when Sellables has items
    ANNOUNCE = "announce",                         -- a chat line when a run starts and ends
    STOP_AFTER_12 = "stopAfter12",                 -- pause selling after every 12 sales
    KEEP_UPGRADES = "keepUpgrades",                -- keep gear that isn't clearly below what is worn where it goes (Rules.GearKeep)
    GEAR_MARGIN = "gearMargin",                    -- item levels under the worn level that still count as "near" it
    KEEP_WARBOUND_GEAR = "keepWarboundGear",       -- keep this expansion's warbound-until-equipped gear for other characters
    SKIP_TRADE_QUESTION = "skipTradeQuestion",     -- answer the game's "you could still trade this" for our sales
    POST_MIN_GOLD = "postMinGold",                 -- Post when the AH estimate is at least this much more (gold)
    BOE_VENDOR_PERCENT = "boeVendorPercent",       -- a Bind-on-Equip item within this % of its AH value is vendored
    BOE_MIN_GOLD = "boeMinGold",                   -- and one that pays less than this much more at the AH (gold)
    BULK_CONFIRM = "bulkConfirm",                  -- ask before a bulk sale
    MAX_PRICE_AGE_DAYS = "maxPriceAgeDays",        -- trust an Auctionator price seen within this many days
    OFFER_TOAST = "offerToast",                    -- current content's Track this run? asks in a toast, not only in chat
    VERSION_CHECK = "versionCheck",                -- share the version with guild and group, a chat line when a newer one is out
  },
  defaults = {
    ["showAtMerchant"] = true,
    ["showAtAuctionHouse"] = true,
    ["announce"] = true,
    ["stopAfter12"] = false,
    ["keepUpgrades"] = true,
    ["gearMargin"] = 0,
    ["keepWarboundGear"] = true,
    ["skipTradeQuestion"] = true,
    ["postMinGold"] = 50,
    ["boeVendorPercent"] = 10,
    ["boeMinGold"] = 5,
    ["bulkConfirm"] = true,
    ["maxPriceAgeDays"] = 3,
    ["offerToast"] = false,
    ["versionCheck"] = true,
  },
  -- Set refuses a failing value and InitializeData puts the default back for
  -- a failing saved one (a hand-edited or damaged file)
  validate = {
    ["showAtMerchant"] = { type = "boolean" },
    ["showAtAuctionHouse"] = { type = "boolean" },
    ["announce"] = { type = "boolean" },
    ["stopAfter12"] = { type = "boolean" },
    ["keepUpgrades"] = { type = "boolean" },
    ["gearMargin"] = { type = "number", min = 0, max = 30, integer = true },
    ["keepWarboundGear"] = { type = "boolean" },
    ["skipTradeQuestion"] = { type = "boolean" },
    ["postMinGold"] = { type = "number", min = 0, max = 1000000, integer = true },
    ["boeVendorPercent"] = { type = "number", min = 0, max = 50, integer = true },
    ["boeMinGold"] = { type = "number", min = 0, max = 1000, integer = true },
    ["bulkConfirm"] = { type = "boolean" },
    ["maxPriceAgeDays"] = { type = "number", min = 0, max = 21, integer = true },
    ["offerToast"] = { type = "boolean" },
    ["versionCheck"] = { type = "boolean" },
  },
  debug = CobysLootSweeper.Debug,
  bus = CobysLootSweeper.EventBus,
  event = CobysLootSweeper.Events.ConfigChanged,
  ensureTables = { "COBYS_LOOT_SWEEPER_WINDOW_STATE" },
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

  CobysLootSweeper.Debug.Log("CONFIG", "Config initialized")
end
