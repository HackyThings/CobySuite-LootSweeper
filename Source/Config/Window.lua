-------------------------------------------------------------------------------
-- CobysLootSweeper Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow),
-- the suite's standard size (680 x 480), built from the suite's styled rows: categories
-- Protection, At the vendor, Auction house, Runs and Your lists
-- a Guide button beside Defaults, staged edits that Apply
-- writes through Config.Set, Cancel, and Defaults. Built at load, so opening
-- it never creates frames in combat; the controls are painted from config on
-- every show, and a ConfigChanged event repaints an open window. Examples
-- read the staged values (window:Get) and never stage anything. The addon
-- is also listed under Options > AddOns with a button that opens this
-- window (CobySuite.UI.RegisterSettingsCategory).
-------------------------------------------------------------------------------

local Config = CobysLootSweeper.Config
local Opt = Config.Options
local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI

local ICONS = {
  shield = "Interface\\Icons\\INV_Shield_06", helm = "Interface\\Icons\\INV_Helmet_03",
  coin = "Interface\\Icons\\INV_Misc_Coin_02", bag = "Interface\\Icons\\INV_Misc_Bag_10",
  gold = "Interface\\Icons\\INV_Misc_Coin_17", watch = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  scales = "Interface\\Icons\\INV_Misc_Note_01", map = "Interface\\Icons\\INV_Misc_Map_01",
}

local function HasAuctionator() return CobysLootSweeper.Prices.Installed("Auctionator") end
local function HasTSM() return CobysLootSweeper.Prices.Installed("TSM") end

-------------------------------------------------------------------------------
-- Examples (staged values, nothing staged)
-------------------------------------------------------------------------------
-- The gear example: the worn slot with the lowest item level, and the
-- level gear must reach to stay protected there
function Config.GearExample(window)
  if window:Get(Opt.KEEP_UPGRADES) == false then
    return "Gear is sorted like any other item while this is off."
  end
  local level, equipLoc, why = CobysLootSweeper.Facts.LowestWorn()
  if not level then
    if why == "empty" then return "Nothing is worn in some slots, so gear for them stays protected." end
    return "Your gear's item level can't be read right now; gear stays protected until it can."
  end
  local margin = tonumber(window:Get(Opt.GEAR_MARGIN)) or 0
  local slot = (equipLoc and _G[equipLoc]) or "lowest slot"
  return string.format("For your %s (item level %d), gear that can reach %d or higher stays protected. Other protections still apply.",
    slot:lower(), level, level - margin)
end

-- The Post example: what an item a vendor buys for 20g must fetch
function Config.PostExample(window)
  local gold = tonumber(window:Get(Opt.POST_MIN_GOLD)) or 0
  local settings = CobysLootSweeper.Rules.Settings()
  settings.postMinCopper = gold * 10000
  local need = CobysLootSweeper.Rules.PostEstimate(20 * 10000, settings)
  return string.format("An item a vendor buys for 20g goes to Post at an auction estimate of about %s.",
    CobysLootSweeper.Utilities.GoldShort(need))
end

-- The Bind-on-Equip example: a 90g item, and where it stops being vendored
function Config.BoEExample(window)
  local settings = CobysLootSweeper.Rules.Settings()
  settings.boeVendorPercent = tonumber(window:Get(Opt.BOE_VENDOR_PERCENT)) or 10
  local floor = (tonumber(window:Get(Opt.BOE_MIN_GOLD)) or 5) * 10000
  local line = math.max(CobysLootSweeper.Rules.BoEVendorLine(90 * 10000, settings), 90 * 10000 + floor)
  return string.format("A Bind-on-Equip item a vendor buys for 90g is sold to a vendor up to an auction value of %s after the cut, and goes to Post above it.",
    CobysLootSweeper.Utilities.GoldShort(line))
end

-------------------------------------------------------------------------------
-- Categories
-------------------------------------------------------------------------------
local function GearOn(get) return get(Opt.KEEP_UPGRADES) ~= false end

local function BuildProtection(panel)
  panel:Section("Always protected", { icon = ICONS.shield })
  panel:Bullets{ items = {
    { title = "Never offered to sell", icon = ICONS.shield, lines = {
      "Looks you haven't collected, and mounts, pets and toys you don't have",
      "Quest items, boxes to open, and items in an equipment set",
      "Legendary, artifact and heirloom items",
      "Anything Loot Sweeper can't prove came from a run",
    } },
    { title = "Protected until you choose Sell on that copy", icon = ICONS.helm, lines = {
      "Gear near or above what you wear (below)",
      "A piece from a token you used, while its look isn't collected",
      "Tokens, recipes, and tradeable loot without a fresh price",
    } },
  } }
  panel:Section("Gear", { icon = ICONS.helm })
  panel:Checkbox{
    key = Opt.KEEP_UPGRADES, label = "Protect possible upgrades",
    description = "Gear that can reach the item level you wear in its slot stays protected, counting its upgrade track. Off: gear is sorted like any other item.",
  }
  panel:Slider{
    key = Opt.GEAR_MARGIN, label = "Also protect gear this many item levels below", min = 0, max = 30, step = 1,
    minLabel = "0", maxLabel = "30", enabledWhen = GearOn,
    description = "0 protects only gear at or above what you wear.",
  }
  panel:Preview{ caption = "Example", text = Config.GearExample, font = U.Fonts.BODY, dimWhen = function(get) return not GearOn(get) end }
  panel:Checkbox{
    key = Opt.KEEP_WARBOUND_GEAR, label = "Protect this expansion's warbound gear",
    description = "Gear that is warbound until equipped stays protected, since another of your characters might wear it.",
  }
  panel:Note{ text = "With Protect possible upgrades on, other-spec gear uses the same item-level threshold. This expansion's set pieces and convertible gear also stay protected." }
end

local function BuildVendor(panel)
  panel:Section("The Loot Sweeper button", { icon = ICONS.coin })
  panel:Checkbox{
    key = Opt.SHOW_AT_MERCHANT, label = "Show the Loot Sweeper button on vendors",
    description = "It sits on the vendor window's edge while loot waits, and shimmers when there is loot you haven't looked at.",
  }
  panel:Section("Selling", { icon = ICONS.bag })
  panel:Checkbox{
    key = Opt.STOP_AFTER_12, label = "Pause every 12 sales",
    description = "The vendor's buyback only holds your last 12 sales; a pause lets you look before going on.",
  }
  panel:Checkbox{
    key = Opt.SKIP_TRADE_QUESTION, label = "Sell group-tradeable loot without the game's extra prompt",
    description = "Selling it gives up the time left to trade it to your group. Loot Sweeper answers only for the items it sells.",
  }
  panel:Checkbox{
    key = Opt.BULK_CONFIRM, label = "Ask before a bulk sale",
    description = "Bulk sell shows what it will sell either way; this adds one last question with the count and the gold.",
  }
end

local function BuildAuction(panel)
  panel:Section("Price sources", { icon = ICONS.gold })
  panel:StatusTiles{ columns = 2, options = {
    { title = "Auctionator", icon = ICONS.gold,
      state = function() return HasAuctionator() and "ok" or "off" end,
      description = function()
        return HasAuctionator() and "Found. Prices for the items it has seen." or "Not installed."
      end,
      tooltip = "Auctionator's prices count only for items it has seen; scan at the auction house to keep them fresh." },
    { title = "TSM", icon = ICONS.scales,
      state = function() return HasTSM() and "ok" or "off" end,
      description = function()
        return HasTSM() and "Found. Market estimates for Post." or "Not installed."
      end,
      tooltip = "TSM's market estimates can put an item in Post, but never count as a fresh price for selling it." },
  } }
  panel:Note{
    visibleWhen = function() return not HasAuctionator() and not HasTSM() end,
    text = "Without a price addon, most tradeable loot stays protected. Junk and bound gear can still be offered when other protections allow it.",
  }
  panel:Section("Worth posting", { icon = ICONS.coin })
  panel:Input{
    key = Opt.POST_MIN_GOLD, label = "Post when the auction house pays at least this much more", unit = "gold",
    numeric = true, digits = true, width = 80,
    description = "For loot other than Bind-on-Equip items: after the 5% cut, and at least twice what a vendor pays.",
  }
  panel:Preview{ caption = "Example", text = Config.PostExample, font = U.Fonts.BODY }
  panel:Slider{
    key = Opt.BOE_VENDOR_PERCENT, label = "Vendor Bind-on-Equip items within this much of their AH value (%)",
    min = 0, max = 50, step = 1, minLabel = "0", maxLabel = "50",
    description = "Posting isn't worth it when a vendor pays nearly as much. Possible upgrades stay protected either way, and vendoring needs a fresh Auctionator price.",
  }
  panel:Input{
    key = Opt.BOE_MIN_GOLD, label = "Also vendor Bind-on-Equip items when the AH pays less than this much more", unit = "gold",
    numeric = true, digits = true, width = 80,
    description = "After the 5% cut, compared with the vendor price. A few gold more isn't worth a listing.",
  }
  panel:Preview{ caption = "Example", text = Config.BoEExample, font = U.Fonts.BODY }
  panel:Section("Fresh prices", { icon = ICONS.watch })
  panel:Dropdown{
    key = Opt.MAX_PRICE_AGE_DAYS, label = "Trust an Auctionator price for",
    labels = { "Today only", "1 day", "3 days", "1 week", "2 weeks", "3 weeks" },
    values = { 0, 1, 3, 7, 14, 21 },
    extraLabel = function(value) return "Custom: " .. tostring(value) .. " days" end,
    enabledWhen = function() return HasAuctionator() end,
    description = function()
      if not HasAuctionator() then return "Needs Auctionator." end
      return "Tradeable loot with an older price stays protected until you scan again."
    end,
  }
  panel:Checkbox{
    key = Opt.SHOW_AT_AUCTION_HOUSE, label = "Open beside the auction house when something is worth posting",
    description = "The window opens on its Post tab.",
  }
end

local function BuildRuns(panel)
  panel:Section("Tracking", { icon = ICONS.map })
  panel:Note{ text = "Runs start by themselves in dungeons and raids from past expansions. Anywhere else, press Start run in the window or type /ls start." }
  panel:Checkbox{
    key = Opt.ANNOUNCE, label = "Say in chat when a run starts and ends",
    description = "The end line sums up what is waiting.",
  }
  -- Current content asks in chat; this adds the toast with its buttons (Task #252)
  panel:Checkbox{
    key = Opt.OFFER_TOAST, label = "Ask with a notice in this season's dungeons, raids and delves",
    description = "Off: a chat line asks, and its [Track this run] link opens the choices. On: a notice near the top of the screen asks too, with the choices on it.",
    tooltip = "Loot Sweeper doesn't track this season's content until you say yes, so it asks first. Old dungeons and raids start by themselves and never ask.",
  }
end

local window = UI.CreateSettingsWindow({
  name    = "CobysLootSweeperOptionsWindow",
  title   = U.WrapColor(CobysLootSweeper.BRAND_COLOR, "Coby's Loot Sweeper") .. " Settings",
  icon    = CobysLootSweeper.ICON,
  config  = Config,
  size    = "standard",
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
    { key = "protection", label = "Protection", build = BuildProtection },
    { key = "vendor", label = "At the vendor", build = BuildVendor },
    { key = "auction", label = "Auction house", build = BuildAuction },
    { key = "runs", label = "Runs", build = BuildRuns },
    {
      -- The lists live in Prefs, staged as edits (UI/KeptLists.lua)
      key = "lists", label = "Your lists",
      config = function() return CobysLootSweeper.KeptLists.Config end,
      build = function(panel) CobysLootSweeper.KeptLists.Build(panel) end,
    },
  },
})

-- For the staged-value scenes (Verify) and the Screens suite (stage, look, then Cancel)
Config._test = { window = window }

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  window:Toggle()
end

-- OpenSettings(categoryKey): opens the window, on that category when given
function Config.OpenSettings(categoryKey)
  window:Open()
  if type(categoryKey) == "string" then window:SelectCategory(categoryKey) end
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
      "Sell the loot from your old-raid and dungeon runs, and see what is worth auctioning. Everything you already had stays safe.",
      "The settings live in the addon's own settings window.",
    },
    slash       = "/ls settings",
    onOpen      = Config.OpenSettings,
  })
end)
