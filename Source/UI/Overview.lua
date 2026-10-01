-------------------------------------------------------------------------------
-- Overview: the top of the Loot Sweeper window, a status banner and four
-- tiles, in the look of Recollect's curator dashboard
--
-- The banner: a tinted strip with an accent stripe, an icon and one sentence
-- in the state's color, which follows the run as it happens ("Tracking Black
-- Temple: 42 new items so far, worth about 1,240g"), and a progress bar while
-- selling; Start / Stop sits at its right. The tiles (Vendor, Post, Keep,
-- History) each show an icon, how many and what they are worth, explain
-- themselves on hover, and pick what shows below (they are its tabs;
-- History swaps in HistoryView). Pure painting from
-- Overview.Model(), which the window builds from the pile, the run and the
-- seller, so the words can be tested without frames.
-------------------------------------------------------------------------------
local Overview = {}
CobysLootSweeper.Overview = Overview

local U = CobySuite_CobysLootSweeper.Utilities
local Utilities = CobysLootSweeper.Utilities

Overview.BANNER_H = 46
Overview.TILE_H = 58
local ICON = 30
local TILE_ICON = 34
local GAP = 8

-- Colors and pictures per tile and banner state
Overview.TILES = {
  { key = "vendor", name = "Vendor", icon = "Interface\\Icons\\INV_Misc_Coin_02", color = "SAGE_GREEN",
    label = "to sell", empty = "nothing to sell yet",
    tip = { "Vendor", "Run loot for a vendor. At a vendor, the quick buttons under the list sell it." } },
  { key = "post", name = "Post", icon = "Interface\\Icons\\INV_Misc_Coin_17", color = "STATUS_GOLD",
    label = "AH estimate", empty = "nothing to post yet",
    tip = { "Post", "Stacks whose AH estimate after the cut meets your Post setting. Check the prices and list them yourself; Loot Sweeper never posts." } },
  { key = "keep", name = "Keep", icon = "Interface\\Icons\\INV_Shield_06", color = "CAUTION_ORANGE",
    label = "kept safe", empty = "nothing kept yet",
    tip = { "Keep", "Run loot Loot Sweeper won't sell. The Why column says what protects each one." } },
  { key = "history", name = "History", icon = "Interface\\Icons\\INV_Misc_Book_09", color = "INFO_BLUE",
    label = "from vendoring", empty = "nothing looted yet", zero = "nothing sold yet",
    tip = { "History", "Everything your runs looted and what became of it, with the gold selling it made. Searchable." } },
}

local STATE = {
  tracking = { color = "SAGE_GREEN", atlas = "UI-LFG-ReadyMark" },
  preparing = { color = "STATUS_GOLD", atlas = "UI-LFG-PendingMark" },
  selling = { color = "INFO_BLUE", texture = "Interface\\Icons\\INV_Misc_Coin_02" },
  done = { color = "SAGE_GREEN", atlas = "UI-LFG-ReadyMark" },
  stopped = { color = "CAUTION_ORANGE", atlas = "UI-LFG-DeclineMark" },
  waiting = { color = "INFO_BLUE", texture = CobysLootSweeper.ICON },
  empty = { color = "LABEL_GRAY", texture = CobysLootSweeper.ICON, dim = true },
}

local function Plural(n, one, many) return n == 1 and one or (many or one .. "s") end

-------------------------------------------------------------------------------
-- The model: what the banner says, and each tile's numbers
-------------------------------------------------------------------------------
-- Model(s, run, preparing, sell, merchant, runName, history) -> { banner = {
-- state, text, share }, tiles = { [key] = { count, value } }, action =
-- "Start" | "Stop" }. runName: the run picked in the window (s is then its
-- loot alone); history: { looted, copper } for the History tile
function Overview.Model(s, run, preparing, sell, merchant, runName, history)
  local model = { tiles = { vendor = s.vendor, post = s.post, keep = s.keep,
    history = { count = history and history.looted or 0, value = history and history.copper or 0 } } }
  model.action = (run or preparing) and "Stop" or "Start"
  local b
  if sell and sell.phase == "selling" then
    b = { state = "selling", share = sell.total > 0 and sell.sold / sell.total or 0,
          text = string.format("Selling %d of %d, %s so far. Stop any time.", math.min(sell.sold + 1, sell.total),
            sell.total, Utilities.Money(sell.copper)) }
  elseif sell and (sell.phase == "done" or sell.phase == "stopped" or sell.phase == "paused") and sell.message and merchant then
    b = { state = sell.phase == "done" and "done" or "stopped", text = sell.message }
  elseif preparing then
    b = { state = "preparing", text = "Getting ready to track: reading your bags so what you carry stays safe." }
  elseif run then
    local c = s.current or { count = 0, value = 0 }
    if c.count == 0 then
      b = { state = "tracking",
            text = string.format("Tracking %s. Your items are safe; new loot shows up here as you pick it up.", run.name or "this run") }
    else
      b = { state = "tracking", text = string.format("Tracking %s: %d new %s so far, worth about %s.", run.name or "this run",
            c.count, Plural(c.count, "item"), Utilities.Money(c.value)) }
    end
  else
    local total = s.vendor.count + s.post.count + s.keep.count
    if total == 0 then
      b = { state = "empty", text = "Nothing waiting yet." }
    elseif merchant and s.vendor.count > 0 then
      b = { state = "waiting", text = string.format("Ready to sell%s: %d %s for %s. Check the list, then press Sell.",
            runName and (" from " .. runName) or "", s.vendor.count, Plural(s.vendor.count, "item"),
            Utilities.Money(s.vendor.value)) }
    elseif runName then
      b = { state = "waiting", text = string.format("Loot from %s is waiting. %s", runName,
            s.vendor.count > 0 and "Visit any vendor to sell it." or "Look it over on the Post and Keep tabs.") }
    else
      local runs = math.max(s.runs or 1, 1)
      b = { state = "waiting", text = string.format("Loot from %d %s is waiting. %s", runs, Plural(runs, "run"),
            s.vendor.count > 0 and "Visit any vendor to sell it." or "Look it over on the Post and Keep tabs.") }
    end
  end
  model.banner = b
  return model
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------
local function Color(name) return U.Colors[name] or U.Colors.HIGHLIGHT_WHITE end

local function SetPicture(texture, def)
  if def.atlas then texture:SetAtlas(def.atlas) else texture:SetTexture(def.texture) end
  texture:SetDesaturated(def.dim == true)
  texture:SetAlpha(def.dim and 0.6 or 1)
end

local function BuildBanner(parent, runButton)
  local banner = CreateFrame("Frame", nil, parent)
  banner:SetHeight(Overview.BANNER_H)
  banner.bg = banner:CreateTexture(nil, "BACKGROUND")
  banner.bg:SetAllPoints()
  banner.stripe = banner:CreateTexture(nil, "BORDER")
  banner.stripe:SetPoint("TOPLEFT")
  banner.stripe:SetPoint("BOTTOMLEFT")
  banner.stripe:SetWidth(3)
  banner.icon = banner:CreateTexture(nil, "ARTWORK")
  banner.icon:SetSize(ICON, ICON)
  banner.icon:SetPoint("LEFT", banner, "LEFT", 12, 0)
  runButton:SetParent(banner)
  runButton:ClearAllPoints()
  runButton:SetPoint("RIGHT", banner, "RIGHT", -10, 0)
  banner.text = banner:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  banner.text:SetPoint("LEFT", banner.icon, "RIGHT", 10, 0)
  banner.text:SetPoint("RIGHT", runButton, "LEFT", -10, 0)
  banner.text:SetJustifyH("LEFT")
  banner.text:SetWordWrap(true)
  banner.track = banner:CreateTexture(nil, "ARTWORK")
  banner.track:SetHeight(4)
  banner.track:SetPoint("BOTTOMLEFT", banner.icon, "BOTTOMRIGHT", 10, -6)
  banner.track:SetPoint("RIGHT", runButton, "LEFT", -10, 0)
  local t = U.Colors.BAR_BG
  banner.track:SetColorTexture(t[1], t[2], t[3], t[4] or 0.8)
  banner.fill = banner:CreateTexture(nil, "OVERLAY")
  banner.fill:SetHeight(4)
  banner.fill:SetPoint("TOPLEFT", banner.track, "TOPLEFT")
  return banner
end

local function BuildTile(parent, def, onClick)
  local tile = CreateFrame("Button", nil, parent)
  tile:SetHeight(Overview.TILE_H)
  tile.key = def.key
  tile.bg = tile:CreateTexture(nil, "BACKGROUND")
  tile.bg:SetAllPoints()
  tile.line = tile:CreateTexture(nil, "BORDER")
  tile.line:SetPoint("BOTTOMLEFT")
  tile.line:SetPoint("BOTTOMRIGHT")
  tile.line:SetHeight(3)
  CobySuite_CobysLootSweeper.UI.AddHoverHighlight(tile)
  tile.icon = tile:CreateTexture(nil, "ARTWORK")
  tile.icon:SetSize(TILE_ICON, TILE_ICON)
  tile.icon:SetPoint("LEFT", tile, "LEFT", 10, 0)
  tile.icon:SetTexture(def.icon)
  tile.value = tile:CreateFontString(nil, "OVERLAY", U.Fonts.TITLE)
  tile.value:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 10, 2)
  tile.value:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
  tile.value:SetJustifyH("LEFT")
  tile.value:SetWordWrap(false)
  tile.label = tile:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  tile.label:SetPoint("BOTTOMLEFT", tile.icon, "BOTTOMRIGHT", 10, -2)
  tile.label:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
  tile.label:SetJustifyH("LEFT")
  tile.label:SetWordWrap(false)
  local gray = U.Colors.LABEL_GRAY
  tile.label:SetTextColor(gray[1], gray[2], gray[3])
  CobySuite_CobysLootSweeper.UI.AddRichTooltip(tile, def.tip[1], { def.tip[2] }, "ANCHOR_BOTTOM")
  tile:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    onClick(def.key)
  end)
  return tile
end

-- Build(window, runButton, onTile, top): the banner and the tiles under the
-- title bar; returns the y offset below them
function Overview.Build(window, runButton, onTile, top)
  local o = { tiles = {} }
  o.banner = BuildBanner(window, runButton)
  o.banner:SetPoint("TOPLEFT", window, "TOPLEFT", 12, top)
  o.banner:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, top)
  local y = top - Overview.BANNER_H - GAP
  for i, def in ipairs(Overview.TILES) do
    o.tiles[i] = BuildTile(window, def, onTile)
  end
  o.top = y
  o.window = window
  Overview.frames = o
  Overview.Layout()
  window:HookScript("OnSizeChanged", function() Overview.Layout() end)
  return y - Overview.TILE_H - GAP
end

-- The tiles share the width
function Overview.Layout()
  local o = Overview.frames
  if not o then return end
  local width = (o.window:GetWidth() or 0) - 24
  local each = (width - GAP * (#o.tiles - 1)) / #o.tiles
  for i, tile in ipairs(o.tiles) do
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", o.window, "TOPLEFT", 12 + (i - 1) * (each + GAP), o.top)
    tile:SetWidth(math.max(each, 60))
  end
end

local function PaintBanner(b)
  local o = Overview.frames
  local def = STATE[b.state] or STATE.empty
  local c = Color(def.color)
  o.banner.bg:SetColorTexture(c[1], c[2], c[3], 0.12)
  o.banner.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
  SetPicture(o.banner.icon, def)
  o.banner.text:SetText(b.text)
  o.banner.text:SetTextColor(c[1], c[2], c[3])
  local bar = b.share ~= nil
  o.banner.track:SetShown(bar)
  o.banner.fill:SetShown(bar and b.share > 0)
  if bar then
    o.banner.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
    o.banner.fill:SetWidth(math.max(1, (o.banner.track:GetWidth() or 0) * math.min(1, b.share)))
  end
end

-- A tile: its name in its color and the count ("Vendor  38"), then what it
-- holds ("284g to sell", "nothing to sell yet")
local function PaintTile(tile, def, numbers, selected)
  local c = Color(def.color)
  local count = numbers.count or 0
  local name = U.WrapColor(U.ColorToHex(count > 0 and c or { 0.65, 0.65, 0.65 }), def.name)
  tile.value:SetText(name .. "  " .. U.WrapColor(count > 0 and "FFFFFF" or "999999", tostring(count)))
  if count == 0 then
    tile.label:SetText(def.empty)
  elseif (numbers.value or 0) > 0 then
    tile.label:SetText(Utilities.GoldShort(numbers.value) .. " " .. def.label)
  elseif def.zero then
    tile.label:SetText(def.zero)
  else
    tile.label:SetText(def.label)
  end
  tile.icon:SetDesaturated(count == 0)
  tile.icon:SetAlpha(count == 0 and 0.5 or 1)
  local bg = U.Colors.CONTENT_BG
  if selected then
    tile.bg:SetColorTexture(c[1], c[2], c[3], 0.16)
    tile.line:SetColorTexture(c[1], c[2], c[3], 1)
  else
    tile.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    tile.line:SetColorTexture(c[1], c[2], c[3], 0.25)
  end
end

-- Paint(model, currentTab)
function Overview.Paint(model, currentTab)
  local o = Overview.frames
  if not o then return end
  PaintBanner(model.banner)
  for i, tile in ipairs(o.tiles) do
    local def = Overview.TILES[i]
    PaintTile(tile, def, model.tiles[def.key] or {}, def.key == currentTab)
  end
end
