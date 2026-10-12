# Coby's Loot Sweeper

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-LootSweeper/main/.publish-meta/icon/cobys-loot-sweeper-224.jpg" width="160" alt="Coby's Loot Sweeper">
</p>

Sell the loot from your old-raid and dungeon runs, and see what is worth auctioning, in WoW Midnight (12.1). Everything you already had stays safe.

## Quick start

1. **Enter a dungeon or raid from a past expansion.** Tracking starts by itself. In this season's content, click **[Track this run]** in the chat line that asks (a setting can also ask with a notice on screen), or press **Start Run**.
2. **Loot as usual.** Only what the run adds counts. What you carried before, and anything from mail, vendors, trades, quests or the bank, is never offered.
3. **Talk to any vendor.** Click the Loot Sweeper button on the vendor window.
4. **Sell.** Use **Junk**, **Bound Gear** or **Other** for a quick sale, or **Bulk Sell...** to pick a preset and preview it first.

## Features

- **Four lists, each with a reason:** **Vendor** (gear and junk, safe to sell), **Sellables** (trade goods and Bind-on-Equip items, with auction prices), **Protected** (kept back because it unlocks something, and what) and **Can't Sell** (loot no vendor buys).
- **Bulk sell:** All junk, Greens, Consumables, Materials, Sellables or Everything, or your own mix by quality and kind.
- **One at a time:** the Tradeable and Warbound buttons on Vendor review their items singly, with both prices and the difference shown.
- **Protected means it can unlock something:** mounts, pets, toys and appearances you don't have, recipes you can still learn, anima, and the materials and items that trade for mounts. Old raid gear is just Vendor.
- **Your choices:** right-click a Protected row and pick **Not Protected** to move it to the normal list, or **Hide From List** on any row.
- **Your lists:** what you keep, remembered Sells and blocked places, per character or shared.
- **History:** what every run looted and what became of it, with the gold it made.
- **Price addons:** Auctionator or TSM for auction estimates; both optional.

## Slash commands

```
/ls                   Open or close the main window
/ls settings          Open or close the settings window
/ls guide             Open or close the feature guide
/ls changelog         Open or close the changelog: what changed in each version
/ls addons            Every addon by Cobanyte, with CurseForge links and pictures (also other, more)
/ls debug             Open or close the debug log window
/ls reset windows     Put every window back to its default place and size
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

- **Protection:** what stays safe, and the newer-version notice.
- **At the vendor:** the vendor button, pausing every 12 sales, the trade prompt, asking before a bulk sale.
- **Auction house:** your price addons, how old a price may be, and whether the window opens beside the auction house.
- **Runs:** the chat line when a run starts and ends, and whether this season's content also asks with a notice on screen.
- **Your lists:** remove entries, copy another character's lists, or share one set.

## Troubleshooting

- **A run didn't start.** Only past-expansion dungeons and raids start by themselves. Press **Start Run** or type `/ls start` before you loot.
- **An item stays in Protected.** Read its reason. Right-click **Not Protected** releases useful-unlock protection for those copies, including missing appearances. Quest items, equipment-set pieces, unopened loot, mixed or interrupted stacks, and unread protection checks cannot be released.
- **Blank AH prices on Sellables.** Scan the auction house with Auctionator; the items are still listed and can be sold to a vendor.
- **Selling stopped: "Your bags changed".** Review what's left, then press the sell button again.

## Install

**CurseForge:** https://www.curseforge.com/wow/addons/cobys-loot-sweeper

**Manual:** drop the `CobysLootSweeper` folder into `Interface/AddOns/`. No dependencies.

## License

GPL-2.0. See [LICENSE](LICENSE).

## Credits

- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Loot Sweeper builds its list of which expansion each dungeon and raid came from; its license notice is in `Source/Data/Instances.lua`.

## Issues / feedback

Found a bug? Run `/ls debug`, press **Copy Last 250** and send the text with a line about what you were doing.

- **Email:** hackythings@gmail.com
- **BugSack errors:** whisper them to **Figment-Illidan** in game.
- **CurseForge:** comment on the [project page](https://www.curseforge.com/wow/addons/cobys-loot-sweeper).
- **GitHub:** [open an issue](https://github.com/HackyThings/CobySuite-LootSweeper/issues) for bugs you can reproduce.
