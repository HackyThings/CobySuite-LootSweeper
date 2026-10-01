-------------------------------------------------------------------------------
-- Guide: the feature guide behind the window's "?", the settings window's
-- Guide button and /ls guide (a new player's first session: start here,
-- then selling, then the rest). A fresh install opens it at its first
-- section (UI/WhatsNew.lua). The suite's standard guide, as Recollect's.
-------------------------------------------------------------------------------
local Guide = {}
CobysLootSweeper.Guide = Guide

local U = CobySuite_CobysLootSweeper.Utilities

Guide.SECTIONS = {
    {
      key = "start", title = "Start here", icon = CobysLootSweeper.ICON,
      summary = "Walk into an old dungeon or raid; tracking starts by itself",
      body = {
        "- Enter a dungeon or raid from a past expansion. A line in chat says tracking has started.",
        "- Farm as usual. Nothing pops up while you play.",
        "- Leave the instance and a line sums up what is waiting.",
        "- Your loot waits as long as you like, through logouts, run by run. The picker over the list shows |cFFFFD100All runs|r or one run, with when it ran.",
        "- Timewalking, Mythic+, this season's dungeons and Remix characters don't start by themselves. Press |cFFFFD100Start|r there if you want them tracked.",
      },
      try = { { "/ls", "Open the Loot Sweeper window any time" } },
    },
    {
      key = "sell", title = "At the vendor", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      summary = "The Loot Sweeper button on the vendor, and the quick buttons",
      body = {
        "- Talk to any vendor. A Loot Sweeper button sits on the vendor window's right edge. It shimmers when a run left loot you haven't looked at.",
        "- Click it: the window opens beside the vendor on the Vendor tab.",
        "- The quick buttons sell part of the list: |cFFFFD100Junk|r, |cFFFFD100Bound gear|r and |cFFFFD100Other|r. You confirm first, and the list shows exactly what will go.",
        "- |cFFFFD100Sell all|r sells those three together. Items go cheapest first, so the vendor's buyback (your last 12 sales) holds the most valuable ones.",
        "- |cFFFFD100Tradeable|r shows items you could still trade or auction one at a time: |cFFFFD100Sell|r, |cFFFFD100Skip|r or |cFFFFD100Stop|r.",
        "- |cFFFFD100Warbound|r does the same for items bound to your warband, such as another class's token: skip any that another of your characters could use.",
        "- Loot a group member could still be traded normally makes the game ask before it's sold. Loot Sweeper answers for the items it sells (a setting).",
        "- Pick one run in the picker to sell only its loot.",
      },
    },
    {
      key = "delete", title = "Loot no vendor buys", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      summary = "Delete it one click at a time, or keep it",
      body = {
        "- |cFFFFD100Can't sell|r lists run loot no vendor buys and nothing protects.",
        "- You see each item and press |cFFFFD100Delete|r or |cFFFFD100Skip|r. The game wants one click per delete.",
        "- Deleting is permanent: there is no buyback.",
      },
    },
    {
      key = "post", title = "Worth posting", icon = "Interface\\Icons\\INV_Misc_Coin_17",
      summary = "Items with a high auction house estimate",
      body = {
        "- The Post tab lists tradeable stacks whose AH estimate, after the 5% cut, is at least twice the vendor price and at least 50g more (change it in settings).",
        "- Estimates come from Auctionator or TSM; a sale isn't promised. At the AH, |cFFFFD100Check prices with Auctionator|r searches for them.",
        "- Loot Sweeper never posts anything itself.",
      },
    },
    {
      key = "keep", title = "Keep and your own choices", icon = "Interface\\Icons\\INV_Misc_Key_03",
      summary = "What is never sold, and how to change one item",
      body = {
        "- Keep holds looks you haven't collected, mounts, pets and toys you don't have, quest items, boxes to open, possible upgrades, and anything Loot Sweeper can't be sure came from the run.",
        "- A run's loot added to a stack you already had keeps the whole stack. The game can't tell which ones are new.",
        "- To change one item, right-click its row and pick |cFFFFD100Keep|r, |cFFFFD100Sell|r or |cFFFFD100Automatic|r. The choice covers every copy in that row.",
        "- To use the choice for this item from now on, tick |cFFFFD100Remember for future copies|r first, then pick. |cFFFFD100Automatic|r forgets it again.",
        "- A tier token for your class says so. Right-click it, pick |cFFFFD100Use token...|r, then press |cFFFFD100Use|r: the piece it gives joins the token's run. At a vendor it first offers to close the vendor, since using an item there would sell it. A token for another class can be sold.",
        "- Banking, equipping, mailing or trading an item takes it out of the pile for good.",
      },
    },
    {
      key = "history", title = "History", icon = "Interface\\Icons\\INV_Misc_Book_09",
      summary = "Everything your runs looted, and the gold it made",
      body = {
        "- The |cFFFFD100History|r tile lists every item your runs looted: when, which run, and what became of it.",
        "- The top line counts what was looted, sold and deleted, and the gold selling made. The run picker narrows it to one run.",
        "- Search by item or run name. |cFFFFD100Clear history|r empties the tab; loot still waiting stays.",
      },
    },
    {
      key = "manual", title = "Other farming", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      summary = "Start and Stop by hand anywhere",
      body = {
        "- Press |cFFFFD100Start|r in the window before farming anywhere else, and |cFFFFD100Stop|r when done.",
        "- Stopping inside an old instance keeps it from starting again until you next go in.",
        "- |cFFFFD100Forget remaining loot|r lets go of every run's loot, or with one run picked, |cFFFFD100Forget this run|r lets go of its loot. The items stay in your bags as ordinary items.",
      },
      try = {
        { "/ls start", "Start a run here" }, { "/ls stop", "End the run" },
        { "/ls settings", "Open or close the settings" }, { "/ls help", "Every command" },
      },
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
