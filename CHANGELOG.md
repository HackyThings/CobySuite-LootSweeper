# Changelog

All notable changes to Coby's Loot Sweeper are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.4] - 2026-10-11

### Added

- **Sellables tab.** Trade goods and Bind-on-Equip items you haven't bound have their own tab, with their auction house prices beside the vendor price, apart from the gear and junk you sell at a vendor. It replaces Post, and you can still sell them to a vendor from there. Without a price addon they are listed with blank prices.
- **Can't Sell tab.** Loot no vendor buys is listed on its own tab, with the one-at-a-time delete steps.
- **Not Protected.** Right-click a Protected row and pick Not Protected: its copies join the normal Vendor, Sellables or Can't Sell list, and nothing is sold by the click. Use Protection Rules undoes it. Quest items, equipment-set pieces, unopened loot and stacks that include items you already had can't be released.
- **Other addons by the same author.** `/ls addons` lists every addon Cobanyte has released, the same list in each of them: what it does, pictures you can click to see bigger, and its CurseForge link to copy into your browser. Addons you already have are marked. It only opens when you ask, and the guide's last section points to it. The list remembers its size and where you left it.
- **Reset windows.** `/ls reset windows` puts every window back to its default place and size after you confirm; your settings and data are not touched.
- **Newer version notice.** When someone in your guild or group has a newer version of Coby's Loot Sweeper, one line in chat says which version is out and which one you have. Your copy shares its version with them quietly, so they hear about a newer one from you too. On by default; turn it off with "Tell me when a newer version is out" in `/ls settings` (Protection).

### Changed

- **Protected holds only what could unlock something.** Mounts, pets, toys and appearances you don't have, recipes you can still learn for a profession you have, anima, the Zereth Mortis materials for mounts and pets, and the items that trade for the Ottuk mounts stay Protected, and the Why says what each is for. Old raid gear, class tokens and "Can be converted" gear now go to Vendor.
- **Shorter right-click menu.** Not Protected (or Use Protection Rules) and Hide From List replace Sell, Automatic, Remember Sell, Keep Every Copy, Ignore and Use Token. Your kept items and blocked places still live under Your lists.
- **History:** item names get the room they need; the column widths reset once.
- The gear and Post price settings are gone from the settings window, since gear is no longer protected for upgrades and Sellables doesn't depend on a price.

### Fixed

- **Protection checks:** items stay Protected when required quest, equipment-set, binding, collection or useful-unlock checks cannot be read. The Why column identifies the unavailable check.
- **Ignore:** a stack that changed size while ignored comes back held when you un-ignore it, so items of your own added to it can never be sold as run loot.
- **Stop Run** in a place you track with "Yes, Always Here" or "Yes, This Time" now stays stopped until you leave, instead of starting again after a `/reload` or inside a delve.

## [0.0.3] - 2026-10-06

### Added

- **Protected tab actions:** "Can't sell (N)..." deletes loot no vendor buys one item at a time, right where that loot is listed. At the auction house, "Check prices with Auctionator" looks up the loot held back for having no recent AH price.
- **Item tooltips** on the one-at-a-time panel and the Use Token window: hover the icon or name to see the item before you sell, delete or use it.

### Changed

- **Track this run?** asks in chat by default: click **[Track this run]** in the line to choose "Yes, always here", "Yes, this time" or "No". A notice on screen with the same choices comes only if you turn on "Ask with a notice in this season's dungeons, raids and delves" under Settings, Runs. The notice lasts 30 seconds (hover to pause); if it runs out, nothing is decided and the chat link still asks.
- **Bulk sell preview:** while Bulk sell is open, the banner shows the stacks and gold it would sell. One preview shows at a time: a quick-sell question closes Bulk sell, and Bulk sell closes the question.
- **Sell and Delete:** a greyed-out button on the one-at-a-time panel now says why, and the delete panel is shorter.
- **Post tab:** its button always reads "Check prices with Auctionator" and works at the auction house.
- **Right-click menu:** Automatic, Sell and Remember Sell come first; "Keep every copy" and Ignore, the lasting choices, sit below the line.
- **Start run and Stop run:** the banner's button says what it does to the run, and is unavailable while a sale runs.
- **Empty tiles** no longer fade out, since you can still click them.
- **Settings:** the Cancel button is now **Undo edits**, with the same job: it drops changes you have not applied.
- Many smaller look and wording improvements across the windows.

### Fixed

- **Track this run:** the notice near the top of the screen now grows to fit its whole message instead of cutting off the last line.
- **Quick sell confirmation:** the buttons underneath no longer show through the bar that asks before Junk, Bound gear or Other sells.
- **Bulk sell:** a pick that matches nothing now says "Nothing matches this pick." instead of claiming no run loot is ready to sell.
- **Stop selling** stays on screen on every tab while a sale runs.
- **Can't sell** waits until a sale finishes, so deleting can no longer interrupt it.
- Several smaller bug fixes.

## [0.0.2] - 2026-10-01

### Added
- **Bulk sell:** choose a preset or customize run loot to vendor, with a preview of the items, gold and protections.
- **Sold elsewhere:** History and gold totals now include sales by you or another addon detected in the vendor's last 12 buyback entries.
- **Ignore:** hide selected copies without selling them, then restore them from the new Ignored tab or History.
- **Bind-on-Equip items:** one goes to Post only when its vendor price is more than 10% below its auction value and the auction house pays at least 5g more; otherwise it's sold to a vendor. Change both under Settings, Auction house. Possible upgrades stay protected.
- **Track this run:** a notice offers tracking in current dungeons, raids and delves, once or on every visit; keystone runs still need `/ls start`.
- **Keep for good:** right-click an item and pick Keep. Loot Sweeper lets go of every copy and never lists that item again on this character.
- **Never track a place:** right-click the window's banner, or type `/ls block`, and Loot Sweeper won't track where you stand again.
- **Your lists:** `/ls kept` manages Keep, Sell and tracking choices, with options to copy or share lists across characters.
- **Careful with gear:** gear is offered only when it is clearly below what you wear where it would go, counting the item level its upgrade track can reach. Other-spec gear uses the same item-level threshold. This expansion's set pieces, convertible gear and warbound gear also stay protected by default. New settings: "Also protect gear this many item levels below" and "Protect this expansion's warbound gear".

### Changed
- **Selling one at a time** shows the vendor price and the auction house price (after its 5% cut) in coins, how much more one pays than the other, and how old the AH price is.
- **Junk is every gray item,** whatever the auction house says, and Junk sells them all. The reasons say it plainly: "Vendor pays at least the AH estimate", "Only 3g more at the AH", "No recent AH price".
- **Settings:** five clearer pages add gear and price examples, price-age choices, and Auctionator and TSM status.
- **The Keep tab is now Protected:** it lists the run loot Loot Sweeper won't sell by itself, with the reason. Keep, in the right-click menu, now means hide an item for good.
- **Your choices are per character:** remembered Sells, and the items you keep, now belong to each character. What you remembered before carries over to every character.
- **Keep replaces the one-copy Keep:** items you had marked Keep one at a time are let go once, and show as Kept in History.
- **Gear stays out of Post:** gear near or above what you wear is no longer listed as worth posting.
- "Never sell possible upgrades" is now "Protect possible upgrades", and compares with the gear in that slot instead of your average item level.
- **Item tooltips in the list:** hovering a row now shows its whole reason, even when the Why column cuts it short, and reminds you that right-click opens the choices and Shift-click links the item in chat.

### Fixed
- A boss drop that starts a quest no longer keeps that boss's loot from being counted.
- Splitting and merging stacks no longer lets your own items be mistaken for run loot.
- Weapons stay protected when your off-hand gear cannot be read.
- Gear decisions refresh when you change equipment.
- **Track this run:** choosing "Yes, this time" now lasts through a login or /reload inside the same instance.
- An old tracking prompt can no longer answer a newer offer.
- Gear with upgrades left stays protected when its highest item level is unknown.
- With one run picked in the window while another run is being tracked, the banner said the tracked run had no loot yet. It now counts the tracked run's loot whichever run is picked.
- Tracking no longer stays paused after certain windows close; the banner names any window still pausing it.

## [0.0.1] - 2026-10-01

### Added
- **Run tracking:** runs start by themselves in most dungeons and raids from past expansions and end when you leave. Start and Stop work anywhere else.
- **Only the run's loot:** what you carried before a run, and anything from the mailbox, a vendor, a trade, a quest reward or the bank, is never offered for sale.
- **Vendor, Post and Keep:** every item from a run is sorted with a short reason, using Auctionator or TSM prices when installed.
- **A button on every vendor:** it shimmers when a run left loot you haven't looked at, and opens Loot Sweeper beside the vendor.
- **Quick sell:** Junk, Bound gear, Other, or all three at once, after you confirm. Items go cheapest first.
- **One item at a time:** loot you could still trade, and warbound loot another of your characters could use, comes up one by one to sell or skip; loot no vendor buys comes up one by one to delete or skip.
- **Loot you could still trade:** Loot Sweeper answers the game's question for the items it sells (a setting, on by default).
- **History:** every item your runs looted, what became of it, and the gold selling made, searchable by item or run.
- **Never sell possible upgrades:** a setting, on by default.
- **Item levels:** gear shows its item level in the lists and in History, sortable.
- **Worth posting:** a list of stacks with a high auction estimate, with a search button for Auctionator.
- **Loot kept run by run:** loot from several runs waits separately. Pick one run in the window to see, sell or forget only its loot, with when it ran.
- **Your own choices:** right-click a row to keep or sell it. Tick Remember for future copies first to keep that choice for the item from then on.
- **Use your class tokens:** a tier token for your class gets a Use token entry on its right-click menu, which opens a small window with a Use button. The piece it gives joins the token's run and is sorted like the rest of its loot. A token for another class can be sold.
- A feature guide, a What's New window that opens after an update, settings in three groups (Windows, Selling, Prices), and an entry in the addon compartment.
