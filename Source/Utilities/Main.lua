local Utilities = CobysLootSweeper.Utilities

---------------------------------------------------------------------------
-- Addon-specific: chat output (branded prefix)
---------------------------------------------------------------------------
Utilities.Message = CobySuite_CobysLootSweeper.Chat.NewMessenger({
  prefix = "[Coby's Loot Sweeper]",
  color = CobysLootSweeper.BRAND_COLOR,
})

---------------------------------------------------------------------------
-- Guards for client reads (12.x can hand addons secret values)
---------------------------------------------------------------------------
-- True when the value is secret (unreadable to addon code); the shared
-- check, kept as a field here so suites can script it
function Utilities.IsSecret(value) return CobySuite_CobysLootSweeper.Utilities.IsSecret(value) end

-- True when the table itself is secret
function Utilities.IsSecretTable(value) return CobySuite_CobysLootSweeper.Utilities.IsSecretTable(value) end

-- pcall that keeps every return value: ok, ...
function Utilities.Try(fn, ...)
  if type(fn) ~= "function" then return false, "not a function" end
  return pcall(fn, ...)
end

-- A whole positive number (an item ID, a count)
function Utilities.IsPositiveInteger(value)
  return type(value) == "number" and not Utilities.IsSecret(value)
    and CobySuite_CobysLootSweeper.Utilities.IsFiniteNumber(value) and value > 0 and value == math.floor(value)
end

-- "12g", "3s 40c": the plain money text used in lists and messages
function Utilities.Money(copper)
  if type(copper) ~= "number" or copper <= 0 then return "0c" end
  return CobySuite_CobysLootSweeper.Utilities.FormatMoneyText(copper)
end

-- When something happened, short: "today 4:32 PM", "yesterday 9:05 AM",
-- "Sep 28"; nil for no time
function Utilities.When(stamp, now)
  if type(stamp) ~= "number" then return nil end
  now = now or time()
  local day = date("%Y%m%d", stamp)
  local clock = (date("%I:%M %p", stamp):gsub("^0", ""))
  if day == date("%Y%m%d", now) then return "today " .. clock end
  if day == date("%Y%m%d", now - 86400) then return "yesterday " .. clock end
  return date("%b ", stamp) .. tonumber(date("%d", stamp))
end

-- Gold-only text for list columns ("12g", "0.5g" below one gold)
function Utilities.GoldShort(copper)
  if type(copper) ~= "number" or copper <= 0 then return "-" end
  local gold = copper / 10000
  if gold >= 100 then return BreakUpLargeNumbers(math.floor(gold)) .. "g" end
  if gold >= 1 then return string.format("%.0fg", gold) end
  return CobySuite_CobysLootSweeper.Utilities.FormatMoneyText(copper)
end
