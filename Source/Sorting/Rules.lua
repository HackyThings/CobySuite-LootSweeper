-- Sorting policy: useful unlocks, proven run loot and game sale limits.
-- "post" remains the internal key for Sellables. No saved tab migration.
local Rules = {}
CobysLootSweeper.Rules = Rules

local VENDOR, POST, KEEP, CANTSELL = "vendor", "post", "keep", "cantsell"
Rules.VENDOR, Rules.POST, Rules.KEEP, Rules.CANTSELL = VENDOR, POST, KEEP, CANTSELL

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

Rules.UNREAD_REASONS = {
  quest = "Cannot check whether this is a quest item",
  set = "Cannot check your saved equipment sets",
  warbound = "Cannot check this item's binding",
  collectible = "Cannot check your collection yet",
  decor = "Cannot check whether this is housing decor",
  anima = "Cannot check whether this adds anima",
  ["mount purchase"] = "Cannot check whether you own its Ottuk mount",
  recipe = "Cannot check whether you can learn this recipe",
  ["appearance token"] = "Cannot check this token's appearances",
}

-- Safety holds are separate from the useful purpose shown in Why.
local function HardKeep(entry, facts)
  if entry.hold == "mixed" then return "Includes items you already had; none of this stack will be sold" end
  if entry.hold then return "Cannot prove this came from your run; it will not be sold" end
  if not facts.loaded then return "Waiting for item details" end
  if facts.unread then return Rules.UNREAD_REASONS[facts.unread] or "Cannot check this item's use yet" end
  if facts.quest then return "Needed for a quest" end
  if facts.openable then return "Contains loot; open it first" end
  if facts.inSet then return "Saved in your equipment set" end
  if facts.collectible and facts.collectible.collected == nil then return "Waiting for your collection to load" end
  if facts.appearance == "unknown" then return "Waiting for your appearances to load" end
end

local function SoftKeep(facts)
  if facts.purpose then return facts.purpose end
  local c = facts.collectible
  if c and c.collected == false then return "You have not collected this " .. (c.kind or "item") end
  if facts.decor then return "Housing decor: you can place it more than once, so every copy is kept" end
  if facts.appearance == "missing" then return "You have not collected this appearance" end
end

-- The legacy Post key is retained for saved sorts and bulk picks.
-- Price changes never move items between these lists.
function Rules.IsSellable(facts)
  if facts.quality == QUALITY_POOR or facts.bound or facts.accountBound then return false end
  return Rules.IsBoE(facts) or facts.classID == 5 or facts.classID == 7
    or facts.classID == 3 or facts.reagent == true
end

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
  local values = Values(entry, facts, quote or {}, settings or {})
  local hard, use = HardKeep(entry, facts), SoftKeep(facts)
  if pref == "keep" then hard = "You chose to keep this" end
  -- Lead with the use, even for a mixed stack. The safety detail remains
  -- available to the menu and tooltip and is checked again before a sale.
  if hard then
    local r = Out(KEEP, use or hard, true, values)
    r.safety = hard
    return r
  end
  if use and not (pref == "sell" and not remembered) then return Out(KEEP, use, false, values) end
  if Rules.IsSellable(facts) then
    values.value = values.ah or 0
    return Out(POST, (facts.hasNoValue or (facts.sellPrice or 0) <= 0) and "Can be auctioned; vendors will not buy it"
      or (values.ah and "Compare the AH estimate with the vendor price"
      or "No AH price yet; you can still choose to vendor it"), false, values)
  end
  if facts.hasNoValue or (facts.sellPrice or 0) <= 0 then
    return Out(CANTSELL, "This item cannot be sold to a vendor", true, values)
  end
  return Out(VENDOR, pref == "sell" and not remembered and "You chose Not Protected"
    or VendorReason(facts, values), false, values)
end

-- Release only the displayed copies, never an item ID or a safety hold.
function Rules.CanUnprotect(row, settings)
  for _, copy in ipairs(row.copies or { row }) do
    if HardKeep(copy.entry, copy.facts) or copy.pref == "keep" then return false end
  end
  return true
end

Rules.CLASS_CONSUMABLE = 0
function Rules.Eligible(entry, facts, quote, pref, settings, remembered, accept)
  local row = Rules.Classify(entry, facts, quote, pref, settings, remembered)
  local flags = { reagent = facts.reagent == true, usable = facts.usable == true,
    consumable = facts.classID == Rules.CLASS_CONSUMABLE,
    warbound = facts.accountBound == true,
    noPrice = Rules.IsSellable(facts) and not (quote and quote.fresh),
    auction = row.ahValue ~= nil and row.ahValue > row.vendorValue }
  if row.bucket == KEEP then
    return false, pref == "keep" and "kept" or (row.hard and "protected" or "held"), row.reason, flags
  end
  if facts.hasNoValue or (facts.sellPrice or 0) <= 0 then
    return false, "novendor", "This item cannot be sold to a vendor", flags
  end
  if accept and accept.bucket and row.bucket ~= accept.bucket then
    return false, "tab", "On another tab", flags
  end
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
  if SoftKeep(facts) and not (pref == "sell" and not remembered) then return false end
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
