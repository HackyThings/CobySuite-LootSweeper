-------------------------------------------------------------------------------
-- Data.Changelog: the in-game changelog (UI/WhatsNew.lua, /ls changelog),
-- one entry per version, newest first. Shown after an update with every
-- version newer than the one the player last ran opened.
--
-- An entry: version (the TOC's), title (a few words), date ("2026-10-02"
-- once released; nil shows "Beta"), and the lists new, changed and fixed,
-- each a line a player reads (the CHANGELOG.md style: what changed for
-- them, no internals), short enough to fit on one line: "Feature: what it
-- does", the part before the first ": " shown in blue, and {/ls} for a
-- command in gold. Keep it in step with CHANGELOG.md: /release adds the
-- entry.
-------------------------------------------------------------------------------
CobysLootSweeper.Data.Changelog = {
  {
    version = "0.0.3",
    title = "Asks in chat, and Bulk sell preview",
    date = "2026-10-06",
    new = {
      "Can't sell: delete unsellable loot one item at a time",
      "Item tooltips on the one-at-a-time panel and Use Token",
    },
    changed = {
      "Track this run: asks in chat; a notice is a setting",
      "Bulk sell: the banner previews the stacks and gold",
      "Sell and Delete: a greyed button says why",
      "Post tab: Check prices with Auctionator",
      "Right-click menu: everyday choices first",
      "Settings: Cancel is now Undo edits",
      "Many smaller look and wording improvements",
    },
    fixed = {
      "Track this run notice shows its whole message",
      "Quick sell bar no longer shows buttons through it",
      "Stop selling stays on screen while a sale runs",
      "Several smaller bug fixes",
    },
  },
  {
    version = "0.0.2",
    title = "Bulk sell and safer gear",
    date = "2026-10-01",
    new = {
      "Bulk sell: pick a preset or customize, with a preview of items and gold",
      "Sold elsewhere: History counts sales detected in the vendor's buyback",
      "Ignore: hide copies without selling, restore from the Ignored tab",
      "Bind-on-Equip: goes to Post only when the auction house clearly pays more",
      "Track this run: a notice offers tracking in current dungeons, raids and delves",
      "Keep for good: right-click an item to never see it again on this character",
      "Never track a place: right-click the banner or type {/ls block}",
      "Your lists: {/ls kept} manages Keep, Sell and tracking choices",
      "Careful with gear: set pieces, convertible and warbound gear stay protected",
    },
    changed = {
      "Selling one at a time: shows vendor and auction prices, the difference and price age",
      "Junk: every gray item, whatever the auction house says",
      "Settings: five clearer pages with examples and Auctionator and TSM status",
      "Protected tab: replaces Keep and lists what Loot Sweeper won't sell, with the reason",
      "Your choices are now per character",
      "Gear near or above what you wear no longer shows in Post",
      "Item tooltips: hover a row to read its whole reason",
    },
    fixed = {
      "A boss drop that starts a quest is now counted",
      "Splitting and merging stacks no longer mistakes your items for run loot",
      "Weapons stay protected when your off-hand gear can't be read",
      "Gear decisions refresh when you change equipment",
      "Yes, this time: tracking now lasts through a login or reload",
      "An old tracking prompt can no longer answer a newer offer",
      "The banner now counts the tracked run's loot whichever run is picked",
      "Tracking no longer stays paused after certain windows close",
    },
  },
  {
    version = "0.0.1",
    title = "First build",
    date = "2026-10-01",
    new = {
      "Run tracking: starts by itself in old dungeons and raids",
      "Your items stay safe: only loot from the run can be sold",
      "Vendor, Post and Keep: every item sorted, with a reason",
      "Vendor button: opens Loot Sweeper beside any vendor",
      "Quick sell: junk, bound gear and the rest, after you confirm",
      "One at a time: tradeable and warbound loot to sell or skip, unsellable loot to delete",
      "Runs: see, sell or forget one run's loot",
      "History: everything looted and the gold it made",
      "Worth posting: items with a high auction estimate",
      "Your call: right-click an item to keep or sell it",
      "Class tokens: use one from its right-click menu",
      "Other farming: {/ls start} and {/ls stop} anywhere",
    },
  },
}
