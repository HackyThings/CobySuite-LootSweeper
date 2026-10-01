-------------------------------------------------------------------------------
-- Prices: what the installed price addons say an item sells for on the AH
--
-- Quote(link) returns
--   { best = the highest per-unit price any source gives (copper) or nil,
--     auctionator = { price, age (days, nil past 21), exact } or nil,
--     tsm = per-unit market value or nil,
--     fresh = true when Auctionator has an exact price seen within
--             Config maxPriceAgeDays (the only price that may send a
--             tradeable item to Vendor, design section 7) }
-- Sources are optional and read through their public APIs only; any error
-- counts as "no price". Oribos Exchange is not read (its API was not
-- checked). Results are cached until Auctionator reports new data
-- (Prices.Hook) or Clear is called.
-------------------------------------------------------------------------------
local Prices = {}
CobysLootSweeper.Prices = Prices

local Try = CobysLootSweeper.Utilities.Try
local CALLER = "CobysLootSweeper"

local seams = {
  Auctionator = function()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api
  end,
  TSM = function() return TSM_API end,
}
Prices._test = { seams = seams }

local cache = {}

function Prices.Clear() cache = {} end

local function PositivePrice(value)
  if type(value) ~= "number" or CobysLootSweeper.Utilities.IsSecret(value) then return nil end
  if not CobySuite_CobysLootSweeper.Utilities.IsFiniteNumber(value) or value <= 0 then return nil end
  return value
end

local function FromAuctionator(link)
  local api = seams.Auctionator()
  if not api or not api.GetAuctionPriceByItemLink then return nil end
  local ok, price = Try(api.GetAuctionPriceByItemLink, CALLER, link)
  price = ok and PositivePrice(price) or nil
  if not price then return nil end
  local okA, age = Try(api.GetAuctionAgeByItemLink, CALLER, link)
  local okE, exact = Try(api.IsAuctionDataExactByItemLink, CALLER, link)
  return {
    price = price,
    age = okA and type(age) == "number" and age or nil,
    exact = okE and exact == true,
  }
end

local function FromTSM(link)
  local api = seams.TSM()
  if not api or not api.ToItemString or not api.GetCustomPriceValue then return nil end
  local ok, itemString = Try(api.ToItemString, link)
  if not ok or type(itemString) ~= "string" then return nil end
  local best
  for _, source in ipairs({ "dbmarket", "dbregionmarketavg" }) do
    local okP, value = Try(api.GetCustomPriceValue, source, itemString)
    value = okP and PositivePrice(value) or nil
    if value and (not best or value > best) then best = value end
  end
  return best
end

-- The prices are cached; fresh is worked out on every call, so a changed
-- day limit applies at once
function Prices.Quote(link)
  if type(link) ~= "string" then return { } end
  local quote = cache[link]
  if not quote then
    quote = { auctionator = FromAuctionator(link), tsm = FromTSM(link) }
    local a = quote.auctionator
    quote.best = a and a.price or nil
    if quote.tsm and (not quote.best or quote.tsm > quote.best) then quote.best = quote.tsm end
    cache[link] = quote
  end
  local a = quote.auctionator
  local maxAge = CobysLootSweeper.Config.Get("maxPriceAgeDays") or 3
  quote.fresh = a ~= nil and a.exact and a.age ~= nil and a.age <= maxAge
  return quote
end

-- Which sources are installed, for the window's footnote and the report
function Prices.Sources()
  local list = {}
  if seams.Auctionator() then list[#list + 1] = "Auctionator" end
  if seams.TSM() then list[#list + 1] = "TSM" end
  return list
end

-- New Auctionator data clears the cache and repaints the view
function Prices.Hook()
  local api = seams.Auctionator()
  if not api or not api.RegisterForDBUpdate then return end
  Try(api.RegisterForDBUpdate, CALLER, function()
    Prices.Clear()
    CobysLootSweeper.EventBus:Fire(CobysLootSweeper.Events.ViewChanged)
  end)
end

-- Auctionator's search tab with these names, at the AH (Auctionator only)
function Prices.SearchAuctionator(names)
  local api = seams.Auctionator()
  if not api or not api.MultiSearchExact or #names == 0 then return false end
  local ok = Try(api.MultiSearchExact, CALLER, names)
  return ok
end
