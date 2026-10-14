-------------------------------------------------------------------------------
-- Guide: the feature guide behind the window's "?", the settings window's
-- Guide button and /ls guide (a new player's first session: start here,
-- then selling, then the rest). A fresh install opens it at its first
-- section (UI/WhatsNew.lua). The suite's standard guide, as Recollect's.
-------------------------------------------------------------------------------
local Guide = {}
CobysLootSweeper.Guide = Guide

local U = CobySuite_CobysLootSweeper.Utilities
local T = CobySuite_CobysLootSweeper.UI.GuideText

Guide.SECTIONS = {
    {
      key = "start", title = "Start here", icon = CobysLootSweeper.ICON,
      summary = "Walk into an old dungeon or raid; tracking starts by itself",
      body = { T.Bullets({
        "Enter a dungeon or raid from a past expansion. A line in chat says tracking has started.",
        "Farm as usual. Nothing gets in your way while you play.",
        "Leave the instance and a line sums up what is waiting.",
        "Loot waits run by run, through logouts. The picker over the list shows " .. T.Key("All runs") .. " or one run.",
        "In this season's content, a chat line asks whether to track the run: click " .. T.Key("[Track this run]") .. " and choose " .. T.Key("Yes, Always Here") .. ", " .. T.Key("Yes, This Time") .. " or " .. T.Key("No") .. ". Settings, Runs can ask with a notice on screen too.",
        "Timewalking, Mythic+ keystone runs and Remix characters are never offered. Press " .. T.Key("Start Run") .. " there if you want them tracked.",
      }) },
      try = { { "/ls", "Open the Loot Sweeper window any time" } },
    },
    {
      key = "sell", title = "At the vendor", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      summary = "The Loot Sweeper button on the vendor, and the quick buttons",
      body = { T.Bullets({
        "Talk to any vendor and click the Loot Sweeper button on its edge. It shimmers when new loot waits.",
        "Click it: the window opens beside the vendor on the Vendor tab.",
        "The quick buttons sell part of the list: " .. T.Key("Junk") .. ", " .. T.Key("Bound Gear") .. " and " .. T.Key("Other") .. ". You confirm first, and the list shows exactly what will go.",
        T.Key("Bulk Sell...") .. " lets you choose a preset or customize what to sell. Review the list first; buyback holds only your last 12 sales.",
        T.Key("Tradeable") .. " shows items you could still trade or auction one at a time: " .. T.Key("Sell") .. ", " .. T.Key("Skip") .. " or " .. T.Key("Stop") .. ".",
        T.Key("Warbound") .. " does the same for items bound to your warband, such as another class's token: skip any that another of your characters could use.",
        "Selling loot you can still trade to your group normally needs an extra prompt. Loot Sweeper can answer it for its own sales.",
        "Pick one run in the picker to sell only its loot.",
      }) },
    },
    {
      key = "delete", title = "Loot no vendor buys", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
      summary = "Delete it one click at a time, or keep it",
      body = { T.Bullets({
        T.Key("Can't Sell") .. " lists run loot no vendor buys and nothing protects.",
        "You see each item and press " .. T.Key("Delete") .. " or " .. T.Key("Skip") .. ". The game wants one click per delete.",
        "Deleting is permanent: there is no buyback.",
      }) },
    },
    {
      key = "post", title = "Sellables", icon = "Interface\\Icons\\INV_Misc_Coin_17",
      summary = "Trade goods and unbound BoE items",
      body = { T.Bullets({
        "Sellables lists trade goods and unbound BoE items, even without an auction price.",
        "At a vendor, Vendor These Items... sells only from Sellables after you review the list.",
        "Estimates come from Auctionator or TSM; a sale isn't promised. At the AH, " .. T.Key("Check Prices with Auctionator") .. " searches for them.",
        "Loot Sweeper never posts anything itself.",
      }) },
    },
    {
      key = "keep", title = "Protected", icon = "Interface\\Icons\\INV_Misc_Key_03",
      summary = "What Loot Sweeper won't sell by itself",
      body = { T.Bullets({
        "Looks you haven't collected, mounts, pets and toys you lack, quest items and boxes to open stay here.",
        "Anima and known materials for collectible rewards stay here too; ordinary old gear goes to Vendor.",
        "So does anything it can't prove came from the run, such as loot added to a stack you already had.",
        "Each row's Why says what protects it.",
      }) },
    },
    {
      key = "choices", title = "Your own choices", icon = "Interface\\Icons\\INV_Misc_Note_01",
      summary = "Release protection or hide a row",
      body = { T.Bullets({
        T.Key("Not Protected") .. " releases the copies in that row; it does not sell them or change future copies.",
        T.Key("Use Protection Rules") .. " undoes that choice.",
        T.Key("Hide From List") .. " hides those copies. The Ignored tab brings them back.",
        "A mixed stack includes items you already had. None of it can be sold or deleted here.",
        T.Key("/ls kept") .. " still manages your saved lists.",
        "Banking, equipping, mailing or trading an item stops tracking that copy.",
      }) },
    },
    {
      key = "history", title = "History", icon = "Interface\\Icons\\INV_Misc_Book_09",
      summary = "Everything your runs looted, and the gold it made",
      body = { T.Bullets({
        "The " .. T.Key("History") .. " tile lists every item your runs looted: when, which run, and what became of it.",
        "The top line counts what was looted, sold and deleted, and the gold made, including sales you or another addon made at a vendor. The run picker narrows it to one run.",
        "Search by item or run name. " .. T.Key("Clear History") .. " empties the tab; loot still waiting stays.",
      }) },
    },
    {
      key = "manual", title = "Other farming", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      summary = "Start Run and Stop Run by hand anywhere",
      body = { T.Bullets({
        "Press " .. T.Key("Start Run") .. " in the window before farming anywhere else, and " .. T.Key("Stop Run") .. " when done.",
        "Stopping inside an old instance keeps it from starting again until you next go in.",
        "To never track a place, right-click the banner at the top of the window and pick " .. T.Key("Never Track Here") .. " (or type " .. T.Key("/ls block") .. " there).",
        T.Key("Forget Remaining Loot") .. " (or " .. T.Key("Forget This Run") .. ") stops listing that loot for good; the items stay in your bags, and a run being tracked carries on.",
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
        T.Key("/ls settings") .. ", or right-click the minimap addon list entry, opens them.",
        "Pages: Protection, At the vendor, Auction house, Runs and Your lists.",
        "Changes wait for " .. T.Key("Apply") .. ". " .. T.Key("Undo Edits") .. " throws them away; " .. T.Key("Defaults") .. " asks first.",
        T.Key("/ls reset windows") .. " puts every window back at its default place and size. Your settings and lists stay.",
      }) },
    },
}
-- The last section in every addon's guide: the list of every addon by Cobanyte
Guide.SECTIONS[#Guide.SECTIONS + 1] = CobySuite_CobysLootSweeper.UI.AddonsGuideSection(CobysLootSweeper.AddonsList)

local guide = CobySuite_CobysLootSweeper.UI.CreateGuideWindow({
  name = "CobysLootSweeperGuideWindow",
  title = U.WrapColor(CobysLootSweeper.BRAND_COLOR, "Coby's Loot Sweeper") .. " Guide",
  icon = CobysLootSweeper.ICON,
  intro = "New here? Start with the first section. Click any heading to open or close it.",
  footer = "Open this guide any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ls guide"),
  sections = Guide.SECTIONS,
  persist = { svTable = function() return COBYS_LOOT_SWEEPER_WINDOW_STATE end, key = "guideWindow" },
})

function Guide.Toggle() guide:Toggle() end

-- Shows the guide at its first section (a fresh install's first login)
function Guide.Show() guide:OpenSection(Guide.SECTIONS[1].key) end
