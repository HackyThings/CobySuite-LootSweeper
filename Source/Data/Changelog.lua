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
