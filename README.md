# Coby's Loot Sweeper

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-LootSweeper/main/.publish-meta/icon/cobys-loot-sweeper-224.jpg" width="160" alt="Coby's Loot Sweeper">
</p>

Sell the loot from your old-raid and dungeon runs, and see what is worth auctioning, in WoW Midnight (12.1). Everything you already had stays safe.

You clear an old raid for transmog or a mount, and walk out with forty pieces of gear you will never wear, a few tokens and a pile of junk, mixed in with everything you already carried. Coby's Loot Sweeper remembers exactly what that run added. At the next vendor it sells that loot, and only that loot, in a couple of clicks.

## The Problem

Junk sellers sell gray items, and sell-by-rule addons look at your whole inventory. Neither knows which of the hundred items in your bags came from the run you just did. Selling raid loot by hand means hovering every item to check its look, its item level and whether a vendor even buys it, then hoping you did not sell the piece you kept on purpose last week. Loot Sweeper follows each item from the moment it lands in your bags, so it only ever offers what a run gave you.

## How It Works

1. **Walk into a dungeon or raid from a past expansion.** Tracking starts by itself and a line in chat says so. Timewalking, Mythic+, this season's dungeons and Remix characters do not start by themselves; press **Start** in the window (or `/ls start`) there, or anywhere else you farm.
2. **Loot as usual.** Nothing pops up while you play. Only what you pick up during the run counts: anything you carried before, and anything from the mailbox, a vendor, a trade, a quest reward or the bank, is never offered for sale.
3. **Finish the run.** Automatic tracking ends when you leave the instance; if you pressed Start yourself, press **Stop** (or `/ls stop`) when you're done. A line in chat sums up what is waiting. Loot waits run by run, through logouts and for as long as you like.
4. **Talk to any vendor.** A Loot Sweeper button sits on the vendor window's right edge. It shimmers when a run left loot you have not looked at yet. Click it and the window opens beside the vendor.
5. **Sell.** The quick buttons sell part of the list after you confirm, while the list shows exactly what will go: **Junk**, **Bound gear** and **Other**, or **Sell all** for those three at once. Items go cheapest first, so the vendor's buyback (your last 12 sales) holds the most valuable ones.
6. **Judge the rest one at a time.** **Tradeable** (items you could still trade or auction) and **Warbound** (items another of your characters could use) come up one item at a time: Sell, Skip or Stop. **Can't sell** walks you through unprotected run loot no vendor buys, to Delete or Skip. It needs no vendor; the game wants one click per delete, and a delete is permanent.

Every item from a run is sorted with a short reason you can read in the list:

- **Vendor:** bound gear whose look you already have, junk, and items with a low auction estimate.
- **Post:** stacks with a high auction estimate (Auctionator or TSM). At the auction house the window opens on its own on this tab, and **Check prices with Auctionator** searches for them. Loot Sweeper never posts anything itself.
- **Keep:** looks you have not collected, mounts, pets and toys you do not have, quest items, boxes to open, possible upgrades, and anything Loot Sweeper cannot be sure came from the run.

More of what it does:

- **Item levels.** Gear shows its item level in a sortable **iLvl** column. The **AH** column shows "bound" or "warbound" for items the auction house will not take.
- **Your call on any item.** Right-click a row: **Keep**, **Sell** or **Automatic**. The choice covers every copy in that row. Tick **Remember for future copies** first to keep it for that item on all your characters; **Automatic** clears it again.
- **Class tokens.** A tier token for your class says so. Right-click it, pick **Use token...**, then press **Use**: the piece it gives joins the token's run and is sorted like the rest of its loot. At a vendor, the button offers to close the vendor first, since using an item there would sell it. A token for another class can be sold.
- **Runs kept apart.** The picker over the list shows **All runs** or one run, with when it ran; **Sell all** and **Forget this run** then work on that run alone.
- **History.** The History tile lists what your runs looted (the last 3,000 items per character): when, which run, and what became of it, such as sold and for how much, deleted, used, equipped, left your bags or combined into another stack. The totals, with the gold vendoring made, are kept for good. Search by item or run name, or pick one run. **Clear history** empties it after asking; loot still waiting stays.
- **Loot you could still trade.** Group loot can be traded to the group for two hours, and the game asks before you sell it. Loot Sweeper answers for the items it sells, and nothing else (a setting, on by default).
- **Nothing lost to a loading screen.** Loot that briefly disappears from the bags (some zones hide them for a moment) is remembered for 14 days and rejoins its run when it comes back. After a relog or `/reload`, Loot Sweeper also finds a run's unsold loot in your bags again from its History. Banking, mailing, trading or equipping an item takes it off the list for good.

## Install

**CurseForge:** https://www.curseforge.com/wow/addons/cobys-loot-sweeper

**Manual:** Drop the `CobysLootSweeper` folder into your `Interface/AddOns/`. No dependencies. Auctionator and TSM are optional price sources; Auctionator can also check current listings.

## Slash Commands

```
/ls                   Open or close the Loot Sweeper window (also /ls show)
/ls settings          Open the settings window (also config, options)
/ls guide             Open or close the feature guide (also tutorial)
/ls changelog         What changed in each version (also whatsnew, news, change)
/ls start             Start tracking a run here (old dungeons and raids start by themselves)
/ls stop              Stop tracking the current run
/ls forget            Forget the remaining loot (the items stay in your bags)
/ls debug             Open or close the debug log window
/ls version           Print the addon version
/ls help              Command list
```

`/sweep`, `/lootsweeper`, `/lootsweep`, `/cobyslootsweeper` and `/cobyslootsweep` work the same as `/ls`. Coby's Loot Sweeper is also in the minimap's addon list: left-click opens the window, right-click the settings.

## Guide and What's New

`/ls guide`, the **?** on the window, or the **Guide** button in the settings window opens a short guide: your first run, the vendor, loot no vendor buys, worth posting, Keep and your own choices, History, and farming anywhere else. It opens by itself the first time you log in with the addon.

`/ls changelog` lists what changed in each version. After an update it opens by itself with every version since the one you last played.

## Settings

Open with `/ls settings`, a right-click on the addon's entry in the minimap addon list, or the Open Settings button on its page under Options > AddOns. The settings are grouped into categories on the left. Changes take effect when you press Apply; Cancel or closing the window throws them away. Defaults asks first, then fills in every default, and nothing changes until you press Apply. Drag the window's bottom-right corner to make it bigger; it keeps that size.

**Windows**
- Loot Sweeper button on vendors (default on)
- Open beside the auction house (default on. The window opens on the Post tab when items are worth posting.)
- Say when a run starts and ends (default on)

**Selling**
- Pause after every 12 sales (default off. The vendor's buyback holds the last 12; selling waits for a click after each 12.)
- Never sell possible upgrades (default on. Gear above the item level you wear on average stays in Keep.)
- Sell loot you could still trade without asking (default on)

**Prices**
- Minimum auction gain (gold) (default 50. A stack goes to Post when its estimate after the 5% cut is at least twice its vendor price and at least this much more.)
- Maximum price age (days) (default 3. A tradeable item other than junk goes to Vendor by itself only when Auctionator saw an exact price for it this recently; a right-click Sell still works without one.)

## Troubleshooting

**A run did not start.**

- Runs start by themselves only in dungeons and raids from past expansions. Timewalking, Mythic+, this season's dungeons and Remix characters are left out. Press **Start** in the window, or `/ls start`, before you loot.
- If you stopped a run inside an instance, it will not start again there until you next go in.

**An item is in Keep and I want it gone.**

- Read its reason in the Why column. A look you have not collected, a quest item or a box to open is protected, and Sell cannot move it. Loot that landed on a stack you already carried keeps the whole stack protected, since the game can't tell your items from the new ones.
- A softer reason (no recent auction price, a possible upgrade, a token, a recipe, a token's piece whose look is not collected yet) moves with a right-click and **Sell**.
- Unprotected run loot no vendor buys shows under **Can't sell** on the Vendor tab, to delete one at a time.

**Tradeable items stay in Keep with "No recent exact AH price".**

- Loot Sweeper only sells an item you could auction by itself when Auctionator saw an exact price for it recently (Maximum price age (days) in settings, 3 by default). Without Auctionator, or after a long break from the auction house, they wait in Keep. Scan the auction house with Auctionator, or right-click an item and choose **Sell**. Junk needs no price.

**There is no Loot Sweeper button on the vendor.**

- The button shows only while run loot is waiting, and only when "Loot Sweeper button on vendors" is on in `/ls settings`. `/ls` opens the window anywhere.

**Selling stopped with "Your bags changed while selling".**

- Something other than Loot Sweeper's own sales left your bags during the batch: often a junk seller such as Scrap selling automatically, sometimes your own clicks. The window notes when Scrap's automatic selling is on. Look over what is left and press the button again, or turn off the other addon's automatic selling.

## License

GPL-2.0. See [LICENSE](LICENSE).

## Credits

- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Loot Sweeper builds its list of which expansion each dungeon and raid came from; its license notice is in `Source/Data/Instances.lua`.

## Issues / Feedback

For bug reports, the cleanest path is the debug log. It is self-contained: it includes the addon version, your WoW build, a snapshot of every setting, and a timestamped event timeline. No need to paste anything else.

**How to capture and send:**

1. Reproduce the issue.
2. Run `/ls debug` to open the debug window and click **Copy Last 250**.
3. Email it to **hackythings@gmail.com** with a sentence about what you were doing.

**Other channels:**

- **BugSack errors:** whisper the report straight to **Figment-Illidan** in-game. BugSack copies the stack trace for you. Mention how to reproduce if you can.
- **CurseForge comments:** drop a note on the [project page](https://www.curseforge.com/wow/addons/cobys-loot-sweeper). Best for general feedback and quick questions.
- **GitHub issues:** [open one here](https://github.com/HackyThings/CobySuite-LootSweeper/issues). Best for reproducible bugs and feature proposals where back-and-forth helps. Attach the debug-log paste here too if it is relevant.
