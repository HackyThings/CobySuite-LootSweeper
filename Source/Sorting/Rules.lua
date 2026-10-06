-------------------------------------------------------------------------------
-- Rules: Vendor, Post or Keep for one pile entry (pure; design section 7)
--
-- Classify(entry, facts, quote, pref, settings, remembered) returns
--   { bucket = "vendor" | "post" | "keep", reason, hard, value, vendorValue, ahValue }
--   reason   the short "Why" text the window shows (our own words)
--   hard     true when a player's Sell choice cannot move it (a protection)
--   value    the row's headline gold (vendor lot for Vendor and Keep, the AH
--            lot after the cut for Post): what the tiles total and the
--            default order uses
-- settings: { postMinCopper, postRatio, cut, keepUpgrades, gearMargin, keepWarboundGear,
--             boeVendorPercent, boeMinCopper }
-- remembered: pref is the item's remembered Sell, not this copy's own
--
-- Group(facts) splits the Vendor list for the quick-sell buttons: "junk"
-- (gray items), "warbound" (bound to the warband: another character could
-- use it, sold one at a time), "bound" (bound gear), "tradeable" (anything
-- that can still be traded, sold one at a time) and "other" (bound items
-- that aren't gear). A token meant for other classes (Facts.otherClass) is
-- no soft Keep: it sells like any other item.
-- Deletable(entry, facts, pref, settings, remembered) is an item no vendor
-- buys that nothing else protects, which the player may delete one click at
-- a time.
--
-- Keep is decided first. A player's Sell only moves a soft Keep (no recent
-- price, a token for this class or of unknown use, a recipe, a used
-- token's piece whose look isn't collected yet) to Vendor, never past a
-- protection: an unproven or mixed stack, a quest item, an unopened
-- container, an equipment set, a legendary or heirloom, a collectible not
-- yet collected, a look not collected, an item a vendor won't buy, or an AH
-- price over the Post line.
--
-- Gear (GearKeep, AllContent-Plan.md section 3) is decided before Post, so a
-- possible upgrade is never offered for auction either: only gear clearly
-- below what is worn where it would go (the item level its upgrade track
-- can reach, under the worn level less the margin) is offered; a set piece
-- from this expansion, gear the game can convert, gear for another spec
-- of the class above that line, and this expansion's warbound-until-
-- equipped gear stay. Gear no spec of the class can use is judged like any
-- other item. An item level that can't be read is a protection; the rest
-- move with a Sell on that copy, never with a remembered Sell (a later copy
-- of the same item can be much stronger).
-------------------------------------------------------------------------------
local Rules = {}
CobysLootSweeper.Rules = Rules

local VENDOR, POST, KEEP = "vendor", "post", "keep"
Rules.VENDOR, Rules.POST, Rules.KEEP = VENDOR, POST, KEEP

local QUALITY_POOR = 0
local QUALITY_EPIC = 4
local QUALITY_LEGENDARY = 5
local CLASS_WEAPON = 2
local CLASS_ARMOR = 4
local CLASS_RECIPE = 9
local CLASS_MISC = 15

local COLLECTIBLE_NAMES = { mount = "Mount", pet = "Pet", toy = "Toy" }

local function Out(bucket, reason, hard, values)
  return {
    bucket = bucket, reason = reason, hard = hard == true,
    value = values.value, vendorValue = values.vendor, ahValue = values.ah,
  }
end

-- The lot's vendor value and its AH value after the cut
local function Values(entry, facts, quote, settings)
  local count = facts.count or entry.count or 1
  local vendor = (facts.sellPrice or 0) * count
  local ah = quote and quote.best and math.floor(quote.best * count * (1 - (settings.cut or CobySuite_CobysLootSweeper.Utilities.AH_CUT))) or nil
  -- No AH estimate for what the AH won't take: bound or warbound
  if facts.bound or facts.accountBound then ah = nil end
  return { vendor = vendor, ah = ah, value = vendor }
end

local BIND_ON_EQUIP = 2   -- Enum.ItemBind.OnEquip

-- A Bind-on-Equip item not bound yet (it could still be auctioned)
function Rules.IsBoE(facts)
  return facts.bindType == BIND_ON_EQUIP and not facts.bound and not facts.accountBound
end

-- BoEVendorLine(vendor, settings): the highest AH value (after the cut) at
-- which a Bind-on-Equip item still goes to a vendor: its vendor price is
-- within boeVendorPercent (default 10) of that AH value (Cobanyte,
-- 2026-10-01, Task #83)
function Rules.BoEVendorLine(vendor, settings)
  local pct = math.min(math.max(settings.boeVendorPercent or 10, 0), 90)
  return vendor / (1 - pct / 100)
end

-- Worth posting: tradeable and not gray, and for a Bind-on-Equip item an AH
-- value above its vendor line and at least boeMinCopper more (a few gold over
-- vendor isn't worth a listing; Task #121); for anything else the AH pays at
-- least postRatio times vendor and at least postMinCopper more
function Rules.WorthPosting(facts, values, settings)
  if facts.bound or facts.accountBound or not values.ah then return false end
  if facts.quality == QUALITY_POOR then return false end   -- gray is junk, whatever the AH says
  if Rules.IsBoE(facts) then
    return values.ah > Rules.BoEVendorLine(values.vendor, settings)
      and values.ah - values.vendor >= (settings.boeMinCopper or 0)
  end
  local ratio = settings.postRatio or 2
  return values.ah >= ratio * values.vendor and values.ah - values.vendor >= (settings.postMinCopper or 0)
end

-- PostEstimate(vendorCopper, settings): the auction estimate (before the
-- cut) at which a lot a vendor buys for vendorCopper goes to Post
function Rules.PostEstimate(vendor, settings)
  local need = math.max((settings.postRatio or 2) * vendor, vendor + (settings.postMinCopper or 0))
  return math.ceil(need / (1 - (settings.cut or CobySuite_CobysLootSweeper.Utilities.AH_CUT)))
end

-- Protections a Sell choice can't move; returns reason or nil
local function HardKeep(entry, facts)
  if entry.hold == "mixed" then
    return string.format("%d new, can't tell from yours", entry.added or 0)
  end
  if entry.hold == "interrupted" then return "Couldn't confirm it came from the run" end
  if not facts.loaded then return "Still loading" end
  if facts.quest then return "Quest item" end
  if facts.openable then return "Open it first" end
  if facts.inSet then return "In an equipment set" end
  if (facts.quality or 0) >= QUALITY_LEGENDARY then return "Legendary, artifact or heirloom" end
  local c = facts.collectible
  if c and c.collected ~= true then
    if c.collected == nil then return (COLLECTIBLE_NAMES[c.kind] or "Collectible") .. ": not sure it's collected" end
    return (COLLECTIBLE_NAMES[c.kind] or "Collectible") .. " not collected yet"
  end
  -- A piece from a used token: the player chose that piece, so its look
  -- not collected yet is a soft Keep a Sell can move (SoftKeep), not this
  if facts.appearance == "missing" and not (entry and entry.fromToken) then return "Appearance not collected" end
  if facts.appearance == "unknown" then return "Appearance not confirmed yet" end
  return nil
end

-- Soft Keeps a Sell choice may move; returns reason or nil
local function SoftKeep(facts, entry)
  if entry and entry.fromToken and facts.appearance == "missing" then
    return "From a token, look not collected yet"
  end
  if facts.classID == CLASS_MISC and (facts.quality or 0) >= QUALITY_EPIC then
    if facts.classToken then return "Token for your class: right-click to use" end
    if not facts.otherClass then return "Token or special item" end
  end
  if facts.classID == CLASS_RECIPE then return "Recipe" end
  return nil
end

-- Gear the player may want: reason, hard; nil when it may be offered
local function GearKeep(facts, settings)
  if not facts.gear then return nil end
  local alt = settings.keepWarboundGear ~= false and facts.warbound and facts.currentExpansion
    and "Another character might use it" or nil
  if settings.keepUpgrades == false or facts.forClass == false then return alt end
  if not facts.reach then return "Item level not read yet", true end
  if not facts.bar then
    if facts.barWhy == "empty" then return "Nothing worn there to compare" end
    return "Your gear's item level not read yet", true
  end
  if facts.reach >= facts.bar - (settings.gearMargin or 0) then
    local level = facts.reach > (facts.level or facts.reach) and string.format("Could reach %d, you wear %d", facts.reach, facts.bar)
      or string.format("Item level %d, you wear %d", facts.reach, facts.bar)
    return (facts.forSpec == false and "Another spec: " or "") .. level
  end
  -- Upgrades left, but how high they go wasn't given: it might pass
  if facts.track == "partial" then return "Can still be upgraded" end
  if facts.currentExpansion and facts.setID then return "Part of a set" end
  if facts.convertible then return "Can be converted" end
  if facts.currentExpansion and facts.track ~= "track" then return "Upgrade track not confirmed" end
  return alt
end
Rules.GearKeep = GearKeep

-- Another class's token: its Classes line leaves this class out, or the game
-- says this character can't use it (Facts.otherClass)
local function OtherClassToken(facts)
  return facts.classID == CLASS_MISC and (facts.quality or 0) >= QUALITY_EPIC and facts.otherClass == true
end

-- Why a vendor beats the AH, in gold where there is an AH value
local function MarketReason(values)
  if not values.ah then return "Low AH value" end
  if values.ah <= values.vendor then return "Vendor pays at least the AH estimate" end
  return string.format("Only %s more at the AH", CobysLootSweeper.Utilities.GoldShort(values.ah - values.vendor))
end

Rules.JUNK_REASON = "Gray item: players rarely buy these"
Rules.NO_PRICE_REASON = "No recent AH price"

local function VendorReason(facts, values)
  if facts.quality == QUALITY_POOR then return Rules.JUNK_REASON end
  if OtherClassToken(facts) then
    return facts.accountBound and "Not for this class; another character might use it" or "Not for your class"
  end
  if facts.accountBound then return "Warbound: another character might use it" end
  if facts.bound then
    if facts.appearance == "collected" then return "Appearance collected" end
    if facts.appearance == "none" then return "Bound, no look to collect" end
    return "Bound"
  end
  return MarketReason(values)
end

function Rules.Classify(entry, facts, quote, pref, settings, remembered)
  settings = settings or {}
  local values = Values(entry, facts, quote or {}, settings)
  if pref == "keep" then return Out(KEEP, "You chose to keep this", true, values) end
  local hard = HardKeep(entry, facts)
  if hard then return Out(KEEP, hard, true, values) end
  local gear, gearHard = GearKeep(facts, settings)
  if gear and (gearHard or not (pref == "sell" and not remembered)) then
    return Out(KEEP, gear, gearHard, values)
  end
  if Rules.WorthPosting(facts, values, settings) then
    values.value = values.ah
    return Out(POST, "AH estimate well above vendor", true, values)
  end
  if facts.hasNoValue or (facts.sellPrice or 0) <= 0 then
    return Out(KEEP, "Vendors won't buy this", true, values)
  end
  local soft = SoftKeep(facts, entry)
  if not soft and not facts.bound and not facts.accountBound and facts.quality ~= QUALITY_POOR
      and not (quote and quote.fresh) then
    soft = Rules.NO_PRICE_REASON
  end
  if soft then
    if pref == "sell" then return Out(VENDOR, "You chose to sell this", false, values) end
    return Out(KEEP, soft, false, values)
  end
  return Out(VENDOR, VendorReason(facts, values), false, values)
end

-- Eligible(entry, facts, quote, pref, settings, remembered, accept): may a
-- bulk sale the player reviewed sell this copy? Walks the same protections
-- as Classify, in the same order, and lifts only the market's reasons: an
-- AH estimate above vendor never holds an item back from a sale the player
-- chose (Cobanyte, Task #121). Items with no recent AH price and warbound
-- items need the player's say (accept.noPrice, accept.warbound). Returns
-- ok, code, reason, flags; code: "kept", "protected", "gear", "novendor",
-- "held", "warbound" or "noprice"; flags: auction (the AH estimate beats
-- vendor), noPrice, warbound, reagent, usable, consumable
Rules.CLASS_CONSUMABLE = 0

function Rules.Eligible(entry, facts, quote, pref, settings, remembered, accept)
  settings, accept = settings or {}, accept or {}
  local values = Values(entry, facts, quote or {}, settings)
  local flags = { reagent = facts.reagent == true, usable = facts.usable == true,
                  consumable = facts.classID == Rules.CLASS_CONSUMABLE }
  if pref == "keep" then return false, "kept", "You chose to keep this", flags end
  local hard = HardKeep(entry, facts)
  if hard then return false, "protected", hard, flags end
  local gear, gearHard = GearKeep(facts, settings)
  if gear and (gearHard or not (pref == "sell" and not remembered)) then return false, "gear", gear, flags end
  if facts.hasNoValue or (facts.sellPrice or 0) <= 0 then return false, "novendor", "Vendors won't buy this", flags end
  local soft = SoftKeep(facts, entry)
  if soft and pref ~= "sell" then return false, "held", soft, flags end
  if facts.accountBound then
    flags.warbound = true
    if not accept.warbound then return false, "warbound", "Warbound: another character might use it", flags end
  end
  if not facts.bound and not facts.accountBound and facts.quality ~= QUALITY_POOR and not (quote and quote.fresh)
      and pref ~= "sell" then
    flags.noPrice = true
    if not accept.noPrice then return false, "noprice", Rules.NO_PRICE_REASON, flags end
  end
  flags.auction = values.ah ~= nil and values.ah > values.vendor
  return true, nil, nil, flags
end

-- The quick-sell group of a Vendor row
function Rules.Group(facts)
  if facts.quality == QUALITY_POOR then return "junk" end
  if facts.accountBound then return "warbound" end
  if not facts.bound then return "tradeable" end
  if facts.classID == CLASS_WEAPON or facts.classID == CLASS_ARMOR then return "bound" end
  return "other"
end

-- No vendor buys it and nothing else protects it (a player's Keep, a hard
-- protection, a soft Keep the player hasn't overruled with Sell)
function Rules.Deletable(entry, facts, pref, settings, remembered)
  if pref == "keep" or not facts.loaded then return false end
  if not (facts.hasNoValue or (facts.sellPrice or 0) <= 0) then return false end
  if HardKeep(entry, facts) then return false end
  local gear, gearHard = GearKeep(facts, settings or {})
  if gear and (gearHard or not (pref == "sell" and not remembered)) then return false end
  if SoftKeep(facts, entry) and pref ~= "sell" then return false end
  return true
end

-- The settings the rules read, from Config
function Rules.Settings()
  local Config = CobysLootSweeper.Config
  return {
    postMinCopper = (Config.Get("postMinGold") or 50) * 10000,
    postRatio = 2,
    cut = CobySuite_CobysLootSweeper.Utilities.AH_CUT,
    keepUpgrades = Config.Get("keepUpgrades") ~= false,
    gearMargin = Config.Get("gearMargin") or 0,
    keepWarboundGear = Config.Get("keepWarboundGear") ~= false,
    boeVendorPercent = Config.Get("boeVendorPercent") or 10,
    boeMinCopper = (Config.Get("boeMinGold") or 5) * 10000,
  }
end
