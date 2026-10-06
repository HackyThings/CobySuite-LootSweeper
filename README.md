# Coby's Loot Sweeper

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-LootSweeper/main/.publish-meta/icon/cobys-loot-sweeper-224.jpg" width="160" alt="Coby's Loot Sweeper">
</p>

Sell the loot from your old-raid and dungeon runs, and see what is worth auctioning, in WoW Midnight (12.1). Everything you already had stays safe.

## Quick Start

1. **Enter a dungeon or raid from a past expansion.** Tracking starts by itself. In this season's content, click **[Track this run]** in the chat line that asks (a setting can also ask with a notice on screen), or press **Start run**.
2. **Loot as usual.** Only what the run adds counts. What you carried before, and anything from mail, vendors, trades, quests or the bank, is never offered.
3. **Talk to any vendor.** Click the Loot Sweeper button on the vendor window.
4. **Sell.** Use **Junk**, **Bound gear** or **Other** for a quick sale, or **Bulk sell...** to pick a preset and preview it first.

## Features

- **Three lists, each with a reason:** **Vendor** (safe to sell), **Post** (worth more at the auction house) and **Protected** (kept back, and why).
- **Bulk sell:** All junk, Greens, Consumables, Materials, Post items or Everything, or your own mix by quality and kind.
- **One at a time:** tradeable and warbound loot comes up singly, with both prices in coins and the difference worked out.
- **Careful with gear:** gear is offered only when it's clearly below what you wear in that slot.
- **Your choices:** right-click a row to **Sell** it, **Keep every copy** of the item for good, or **Ignore** the copies in that row.
- **Your lists:** what you keep, remembered Sells and blocked places, per character or shared.
- **History:** what every run looted and what became of it, with the gold it made.
- **Class tokens:** use a token from its row; the piece joins the token's run.
- **Price addons:** Auctionator or TSM for auction estimates; both optional.

## Slash Commands

```
/ls                   Open or close the main window
/ls settings          Open or close the settings window
/ls guide             Open or close the feature guide
/ls changelog         Open or close the changelog: what changed in each version
/ls debug             Open or close the debug log window
/ls start             Start tracking a run here (old dungeons and raids start by themselves)
/ls stop              Stop tracking the current run
/ls forget            Forget the remaining loot (the items stay in your bags)
/ls kept              Open Your lists: kept items, remembered Sells and blocked places
/ls block             Never track where you stand (undo it in /ls kept)
/ls version           Print the addon version
/ls help              Show this help
```

`/sweep`, `/lootsweeper` and `/lootsweep` work the same. The addon list on the minimap: left-click opens the window, right-click the settings.

## Settings

`/ls settings`, or right-click the minimap addon list entry. Changes wait for **Apply**.

- **Protection:** protect possible upgrades, how many item levels below still count, warbound gear.
- **At the vendor:** the vendor button, pausing every 12 sales, the trade prompt, asking before a bulk sale.
- **Auction house:** when to post, when a Bind-on-Equip item goes to a vendor instead, how old a price may be, and whether the window opens beside the auction house.
- **Runs:** the chat line when a run starts and ends, and whether this season's content also asks with a notice on screen.
- **Your lists:** remove entries, copy another character's lists, or share one set.

## Troubleshooting

- **A run didn't start.** Only past-expansion dungeons and raids start by themselves. Press **Start run** or type `/ls start` before you loot.
- **An item stays in Protected.** Read its reason. A soft one moves with right-click **Sell**; a look you haven't collected, a quest item or a box to open never does.
- **"No recent AH price".** Scan the auction house with Auctionator, or right-click the item and pick **Sell**.
- **Selling stopped: "Your bags changed".** Another seller (Scrap, for one) sold something mid-batch. Press the button again.

## Install

**CurseForge:** https://www.curseforge.com/wow/addons/cobys-loot-sweeper

**Manual:** drop the `CobysLootSweeper` folder into `Interface/AddOns/`. No dependencies.

## License

GPL-2.0. See [LICENSE](LICENSE).

## Credits

- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Loot Sweeper builds its list of which expansion each dungeon and raid came from; its license notice is in `Source/Data/Instances.lua`.

## Issues / Feedback

Found a bug? Run `/ls debug`, press **Copy Last 250** and send the text with a line about what you were doing.

- **Email:** hackythings@gmail.com
- **BugSack errors:** whisper them to **Figment-Illidan** in game.
- **CurseForge:** comment on the [project page](https://www.curseforge.com/wow/addons/cobys-loot-sweeper).
- **GitHub:** [open an issue](https://github.com/HackyThings/CobySuite-LootSweeper/issues) for bugs you can reproduce.
