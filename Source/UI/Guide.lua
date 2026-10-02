-------------------------------------------------------------------------------
-- Guide: the feature guide behind the window's "?", the settings window's
-- Guide button and /ls guide (a new player's first session: start here,
-- then selling, then the rest). A fresh install opens it at its first
-- section (UI/WhatsNew.lua). The suite's standard guide, as Recollect's.
-------------------------------------------------------------------------------
local Guide = {}
CobysLootSweeper.Guide = Guide

local U = CobySuite_CobysLootSweeper.Utilities
local GOLD = "|cFF" .. U.Colors.TEXT_GOLD   -- the guide's highlights
local T = CobySuite_CobysLootSweeper.UI.GuideText

Guide.SECTIONS = {
    {
      key = "start", title = "Start here", icon = CobysLootSweeper.ICON,
      summary = "Walk into an old dungeon or raid; tracking starts by itself",
      body = { T.Bullets({
        "Enter a dungeon or raid from a past expansion. A line in chat says tracking has started.",
        "Farm as usual. Nothing pops up while you play.",
        "Leave the instance and a line sums up what is waiting.",
        "Loot waits run by run, through logouts. The picker over the list shows " .. GOLD .. "All runs|r or one run.",
        "In this season's content, click " .. GOLD .. "[Track this run]|r when it's offered: " .. GOLD .. "Yes, always here|r, " .. GOLD .. "Yes, this time|r or " .. GOLD .. "No|r.",
        "Timewalking, Mythic+ keystone runs and Remix characters are never offered. Press " .. GOLD .. "Start|r there if you want them tracked.",
      }) },
      try = { { "/ls", "Open the Loot Sweeper window any time" } },
    },
    {
      key = "sell", title = "At the vendor", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      summary = "The Loot Sweeper button on the vendor, and the quick buttons",
      body = { T.Bullets({
        "Talk to any vendor and click the Loot Sweeper button on its edge. It shimmers when new loot waits.",
        "Click it: the window opens beside the vendor on the Vendor tab.",
        "The quick buttons sell part of the list: " .. GOLD .. "Junk|r, " .. GOLD .. "Bound gear|r and " .. GOLD .. "Other|r. You confirm first, and the list shows exactly what will go.",
        "" .. GOLD .. "Bulk sell...|r lets you choose a preset or customize what to sell. Review the list first; buyback holds only your last 12 sales.",
        "" .. GOLD .. "Tradeable|r shows items you could still trade or auction one at a time: " .. GOLD .. "Sell|r, " .. GOLD .. "Skip|r or " .. GOLD .. "Stop|r.",
        "" .. GOLD .. "Warbound|r does the same for items bound to your warband, such as another class's token: skip any that another of your characters could use.",
        "Selling loot you can still trade to your group normally needs an extra prompt. Loot Sweeper can answer it for its own sales.",
        "Pick one run in the picker to sell only its loot.",
      }) },
    },
    {
      key = "delete", title = "Loot no vendor buys", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      summary = "Delete it one click at a time, or keep it",
      body = { T.Bullets({
        "" .. GOLD .. "Can't sell|r lists run loot no vendor buys and nothing protects.",
        "You see each item and press " .. GOLD .. "Delete|r or " .. GOLD .. "Skip|r. The game wants one click per delete.",
        "Deleting is permanent: there is no buyback.",
      }) },
    },
    {
      key = "post", title = "Worth posting", icon = "Interface\\Icons\\INV_Misc_Coin_17",
      summary = "Items with a high auction house estimate",
      body = { T.Bullets({
        "Post lists tradeable loot worth auctioning after the 5% cut. Change its thresholds in Settings, Auction house.",
        "By default, loot needs twice the vendor price and 50g more. Bind-on-Equip goes to a vendor within 10% or 5g of its AH value.",
        "Estimates come from Auctionator or TSM; a sale isn't promised. At the AH, " .. GOLD .. "Check prices with Auctionator|r searches for them.",
        "Loot Sweeper never posts anything itself.",
      }) },
    },
    {
      key = "keep", title = "Protected", icon = "Interface\\Icons\\INV_Misc_Key_03",
      summary = "What Loot Sweeper won't sell by itself",
      body = { T.Bullets({
        "Looks you haven't collected, mounts, pets and toys you lack, quest items and boxes to open stay here.",
        "Gear stays unless it's clearly below what you wear in that slot, counting its upgrade track.",
        "So does anything it can't prove came from the run, such as loot added to a stack you already had.",
        "Each row's Why says what protects it.",
      }) },
    },
    {
      key = "choices", title = "Your own choices", icon = "Interface\\Icons\\INV_Misc_Note_01",
      summary = "Keep, Sell and Ignore one item",
      body = { T.Bullets({
        "Right-click a row: " .. GOLD .. "Keep|r hides every copy of that item for good on this character.",
        "" .. GOLD .. "Sell|r marks the row's copies for selling at a vendor. Some protections can't be overridden.",
        "Tick " .. GOLD .. "Remember Sell for future copies|r to reuse it; future gear still gets upgrade checks. " .. GOLD .. "Automatic|r restores the normal rules.",
        "" .. GOLD .. "Ignore|r hides one copy; the " .. GOLD .. "Ignored|r tab brings it back.",
        "" .. GOLD .. "/ls kept|r lists what you keep, remembered Sells and blocked places. Copy another character's, or share one set.",
        "A token for your class: right-click it, pick " .. GOLD .. "Use token...|r, then " .. GOLD .. "Use|r. The piece joins the token's run.",
        "Banking, equipping, mailing or trading an item stops tracking that copy.",
      }) },
    },
    {
      key = "history", title = "History", icon = "Interface\\Icons\\INV_Misc_Book_09",
      summary = "Everything your runs looted, and the gold it made",
      body = { T.Bullets({
        "The " .. GOLD .. "History|r tile lists every item your runs looted: when, which run, and what became of it.",
        "The top line counts what was looted, sold and deleted, and the gold selling made. The run picker narrows it to one run.",
        "Search by item or run name. " .. GOLD .. "Clear history|r empties the tab; loot still waiting stays.",
      }) },
    },
    {
      key = "manual", title = "Other farming", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      summary = "Start and Stop by hand anywhere",
      body = { T.Bullets({
        "Press " .. GOLD .. "Start|r in the window before farming anywhere else, and " .. GOLD .. "Stop|r when done.",
        "Stopping inside an old instance keeps it from starting again until you next go in.",
        "To never track a place, right-click the banner at the top of the window and pick " .. GOLD .. "Never track here|r (or type " .. GOLD .. "/ls block|r there).",
        "" .. GOLD .. "Forget remaining loot|r (or " .. GOLD .. "Forget this run|r) stops tracking it; the items stay in your bags.",
      }) },
      try = {
        { "/ls start", "Start a run here" }, { "/ls stop", "End the run" },
        { "/ls kept", "What you keep and what you blocked" }, { "/ls settings", "Open or close the settings" },
        { "/ls help", "Every command" },
      },
    },
    {
      key = "settings", title = "Settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      summary = "Change how careful Loot Sweeper is",
      body = { T.Bullets({
        "" .. GOLD .. "/ls settings|r, or right-click the minimap addon list entry, opens them.",
        "Pages: Protection, At the vendor, Auction house, Runs and Your lists.",
        "Changes wait for " .. GOLD .. "Apply|r. " .. GOLD .. "Cancel|r throws them away; " .. GOLD .. "Defaults|r asks first.",
      }) },
    },
}

local guide = CobySuite_CobysLootSweeper.UI.CreateGuideWindow({
  name = "CobysLootSweeperGuideWindow",
  title = "Coby's Loot Sweeper Guide",
  icon = CobysLootSweeper.ICON,
  intro = "New here? Start with the first section. Click any heading to open or close it.",
  footer = "Open this guide any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ls guide"),
  sections = Guide.SECTIONS,
  persist = { svTable = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end, key = "guideWindow" },
})

-- The window, for the suites
Guide._test = { window = guide }

function Guide.Toggle() guide:Toggle() end

-- Shows the guide at its first section (a fresh install's first login)
function Guide.Show() guide:OpenSection(Guide.SECTIONS[1].key) end
