-------------------------------------------------------------------------------
-- Rules: Vendor, Post or Keep for one pile entry (pure; design section 7)
--
-- Classify(entry, facts, quote, pref, settings) returns
--   { bucket = "vendor" | "post" | "keep", reason, hard, value, vendorValue, ahValue }
--   reason   the short "Why" text the window shows (our own words)
--   hard     true when a player's Sell choice cannot move it (a protection)
--   value    what the row's value column shows (vendor lot for Vendor and
--            Keep, the AH lot after the cut for Post)
-- settings: { postMinCopper, postRatio, cut, keepUpgrades }
--
-- Group(facts) splits the Vendor list for the quick-sell buttons: "junk"
-- (gray items), "warbound" (bound to the warband: another character could
-- use it, sold one at a time), "bound" (bound gear), "tradeable" (anything
-- that can still be traded, sold one at a time) and "other" (bound items
-- that aren't gear). A token meant for other classes (Facts.otherClass) is
-- no soft Keep: it sells like any other item.
-- Deletable(entry, facts, pref, settings) is an item no vendor buys that nothing else
-- protects, which the player may delete one click at a time.
--
-- Keep is decided first. A player's Keep always wins; a player's Sell only
-- moves a soft Keep (no recent price, a token for this class or of unknown
-- use, a recipe, a possible upgrade, a used token's piece whose look isn't
-- collected yet) to Vendor, never past a protection: an unproven or mixed stack, a
-- quest item, an unopened container, an equipment set, a legendary or
-- heirloom, a collectible not yet collected, a look not collected, an item a
-- vendor won't buy, or an AH price over the Post line.
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
  local ah = quote and quote.best and math.floor(quote.best * count * (1 - (settings.cut or 0.05))) or nil
  -- No AH estimate for what the AH won't take: bound or warbound
  if facts.bound or facts.accountBound then ah = nil end
  return { vendor = vendor, ah = ah, value = vendor }
end

-- Worth posting: tradeable, the AH pays at least postRatio times vendor and
-- at least postMinCopper more
function Rules.WorthPosting(facts, values, settings)
  if facts.bound or facts.accountBound or not values.ah then return false end
  local ratio = settings.postRatio or 2
  return values.ah >= ratio * values.vendor and values.ah - values.vendor >= (settings.postMinCopper or 0)
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
local function SoftKeep(facts, settings, entry)
  if entry and entry.fromToken and facts.appearance == "missing" then
    return "From a token, look not collected yet"
  end
  if facts.classID == CLASS_MISC and (facts.quality or 0) >= QUALITY_EPIC then
    if facts.classToken then return "Token for your class: right-click to use" end
    if not facts.otherClass then return "Token or special item" end
  end
  if facts.classID == CLASS_RECIPE then return "Recipe" end
  if facts.upgrade and settings.keepUpgrades ~= false then return "Might be an upgrade" end
  return nil
end

-- Another class's token: its Classes line leaves this class out, or the game
-- says this character can't use it (Facts.otherClass)
local function OtherClassToken(facts)
  return facts.classID == CLASS_MISC and (facts.quality or 0) >= QUALITY_EPIC and facts.otherClass == true
end

local function VendorReason(facts)
  if facts.quality == QUALITY_POOR then return "Junk" end
  if OtherClassToken(facts) then
    return facts.accountBound and "Not for this class; another character might use it" or "Not for your class"
  end
  if facts.accountBound then return "Warbound: another character might use it" end
  if facts.bound then
    if facts.appearance == "collected" then return "Appearance collected" end
    if facts.appearance == "none" then return "Bound, no look to collect" end
    return "Bound"
  end
  return "Low AH value"
end

function Rules.Classify(entry, facts, quote, pref, settings)
  settings = settings or {}
  local values = Values(entry, facts, quote or {}, settings)
  if pref == "keep" then return Out(KEEP, "You chose to keep this", true, values) end
  local hard = HardKeep(entry, facts)
  if hard then return Out(KEEP, hard, true, values) end
  if Rules.WorthPosting(facts, values, settings) then
    values.value = values.ah
    return Out(POST, "AH estimate well above vendor", true, values)
  end
  if facts.hasNoValue or (facts.sellPrice or 0) <= 0 then
    return Out(KEEP, "Vendors won't buy this", true, values)
  end
  local soft = SoftKeep(facts, settings, entry)
  if not soft and not facts.bound and not facts.accountBound and facts.quality ~= QUALITY_POOR
      and not (quote and quote.fresh) then
    soft = "No recent exact AH price"
  end
  if soft then
    if pref == "sell" then return Out(VENDOR, "You chose to sell this", false, values) end
    return Out(KEEP, soft, false, values)
  end
  return Out(VENDOR, VendorReason(facts), false, values)
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
function Rules.Deletable(entry, facts, pref, settings)
  if pref == "keep" or not facts.loaded then return false end
  if not (facts.hasNoValue or (facts.sellPrice or 0) <= 0) then return false end
  if HardKeep(entry, facts) then return false end
  if SoftKeep(facts, settings or {}, entry) and pref ~= "sell" then return false end
  return true
end

-- The settings the rules read, from Config
function Rules.Settings()
  local Config = CobysLootSweeper.Config
  return {
    postMinCopper = (Config.Get("postMinGold") or 50) * 10000,
    postRatio = 2,
    cut = CobySuite_CobysLootSweeper.Utilities.AH_CUT or 0.05,
    keepUpgrades = Config.Get("keepUpgrades") ~= false,
  }
end
