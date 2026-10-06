-------------------------------------------------------------------------------
-- Overview: the top of the Loot Sweeper window, a status banner and five
-- tiles, in the look of Recollect's curator dashboard
--
-- The banner: a tinted strip with an accent stripe, an icon and one sentence
-- in the state's color, which follows the run as it happens ("Tracking Black
-- Temple: 42 new items so far, worth about 1,240g"), and a progress bar while
-- selling; Start / Stop sits at its right. The tiles (Vendor, Post,
-- Protected, History and Ignored) show counts and values, explain
-- themselves on hover, and pick what shows below (they are its tabs;
-- History and Ignored swap in their own views). Pure painting from
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
local GAP = U.Spacing.GROUP_GAP

-- Colors and pictures per tile and banner state
Overview.TILES = {
  { key = "vendor", name = "Vendor", icon = "Interface\\Icons\\INV_Misc_Coin_02", color = "SAGE_GREEN",
    label = "to sell", empty = "nothing to sell yet",
    tip = { "Vendor", "Run loot for a vendor. At a vendor, the quick buttons under the list sell it." } },
  { key = "post", name = "Post", icon = "Interface\\Icons\\INV_Misc_Coin_17", color = "STATUS_GOLD",
    label = "AH estimate", empty = "nothing to post yet",
    tip = { "Post", "Stacks whose AH estimate after the cut meets your Post setting. Check the prices and list them yourself; Loot Sweeper never posts." } },
  { key = "keep", name = "Protected", icon = "Interface\\Icons\\INV_Shield_06", color = "CAUTION_ORANGE",
    label = "protected", empty = "nothing protected yet",
    tip = { "Protected", "Loot from your runs that Loot Sweeper won't sell by itself. The Why column says what protects each one." } },
  { key = "history", name = "History", icon = "Interface\\Icons\\INV_Misc_Book_09", color = "INFO_BLUE",
    label = "from vendoring", empty = "nothing looted yet", zero = "nothing sold yet", zeroShort = "none sold",
    tip = { "History", "Everything your runs looted and what became of it, with the gold selling it made. Searchable." } },
  { key = "ignored", name = "Ignored", icon = "Interface\\Icons\\INV_Misc_Eye_01", color = "LABEL_GRAY",
    label = "ignored", empty = "nothing ignored", zero = "can be un-ignored",
    tip = { "Ignored", "Copies you chose to ignore. They stay in your bags; un-ignore one to list it again. Searchable." } },
}

local STATE = {
  tracking = { color = "SAGE_GREEN", atlas = "UI-LFG-ReadyMark" },
  preparing = { color = "STATUS_GOLD", atlas = "UI-LFG-PendingMark" },
  paused = { color = "STATUS_GOLD", atlas = "UI-LFG-PendingMark" },
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
-- Model(s, run, preparing, sell, merchant, runName, history, ignored, paused, preview) -> {
-- banner = { state, text, share }, tiles = { [key] = { count, value } },
-- action = "Start" | "Stop" }. runName: the run picked in the window (s is
-- then its loot alone); history: { looted, copper } for the History tile;
-- ignored: how many copies are ignored; paused: the window holding a run's
-- loot back (Fences.Paused), or nil; preview: { stacks, copper } while the
-- list previews a Bulk sell plan
function Overview.Model(s, run, preparing, sell, merchant, runName, history, ignored, paused, preview)
  local model = { tiles = { vendor = s.vendor, post = s.post, keep = s.keep,
    history = { count = history and history.looted or 0, value = history and history.copper or 0 },
    ignored = { count = ignored or 0, value = 0 } } }
  model.action = (run or preparing) and "Stop" or "Start"
  local b
  if sell and sell.phase == "selling" then
    b = { state = "selling", share = sell.total > 0 and sell.sold / sell.total or 0,
          text = string.format("Selling %d of %d, %s so far. Stop any time.", math.min(sell.sold + 1, sell.total),
            sell.total, Utilities.Money(sell.copper)) }
  elseif sell and (sell.phase == "done" or sell.phase == "stopped" or sell.phase == "paused") and sell.message and merchant then
    b = { state = sell.phase == "done" and "done" or "stopped", text = sell.message }
  elseif preview and merchant and preview.stacks == 0 then
    b = { state = "waiting", text = "Bulk sell preview: nothing matches this pick." }
  elseif preview and merchant then
    b = { state = "waiting", text = string.format("Bulk sell preview: %d %s for %s. Review the list, then sell from the Bulk sell panel.",
          preview.stacks, Plural(preview.stacks, "stack"), Utilities.Money(preview.copper)) }
  elseif preparing then
    b = { state = "preparing", text = "Getting ready to track: reading your bags so what you carry stays safe." }
  elseif run and paused then
    b = { state = "paused", text = string.format("Tracking %s, paused while %s is open: nothing that arrives now counts as loot.",
          run.name or "this run", paused) }
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
      b = { state = "waiting", text = string.format("Ready to sell%s: %d %s for %s. Bulk sell... lets you choose what goes.",
            runName and (" from " .. runName) or "", s.vendor.count, Plural(s.vendor.count, "item"),
            Utilities.Money(s.vendor.value)) }
    elseif runName then
      b = { state = "waiting", text = string.format("Loot from %s is waiting. %s", runName,
            s.vendor.count > 0 and "Visit any vendor to sell it." or "Look it over on the Post and Protected tabs.") }
    else
      local runs = math.max(s.runs or 1, 1)
      b = { state = "waiting", text = string.format("Loot from %d %s is waiting. %s", runs, Plural(runs, "run"),
            s.vendor.count > 0 and "Visit any vendor to sell it." or "Look it over on the Post and Protected tabs.") }
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

local function Numbers(ctx, def) return ctx.tiles and ctx.tiles[def.key] or {} end

-- A tile's live fields, from the model Paint last gave (ctx.tiles): its name
-- in its color and the count ("Vendor  38"), then what it holds ("284g to
-- sell", "nothing to sell yet"; short: "284g", "none yet"). On the shared
-- stat tiles (Task #116): each tile's own color as its accent, the large
-- font giving way to the body font and the line to its short form when the
-- tile is narrow (the fit Verify's q90-01 asked for). An empty tile is
-- never faded, since it stays clickable: its gray name and count and its
-- "none yet" say it is empty (Task #235)
local function StatTile(def)
  local c = Color(def.color)
  return {
    key = def.key, icon = def.icon, accent = c,
    value = function(ctx)
      local count = Numbers(ctx, def).count or 0
      return U.WrapColor(U.ColorToHex(count > 0 and c or U.Colors.LABEL_GRAY), def.name) .. "  "
        .. U.WrapColor(U.ColorToHex(count > 0 and U.Colors.HIGHLIGHT_WHITE or U.Colors.DISABLED_GRAY), tostring(count))
    end,
    label = function(ctx)
      local n = Numbers(ctx, def)
      if (n.count or 0) == 0 then return def.empty end
      if (n.value or 0) > 0 then return Utilities.GoldShort(n.value) .. " " .. def.label end
      return def.zero or def.label
    end,
    labelShort = function(ctx)
      local n = Numbers(ctx, def)
      if (n.count or 0) == 0 then return "none yet" end
      if (n.value or 0) > 0 then return Utilities.GoldShort(n.value) end
      return def.zeroShort
    end,
    tooltipFill = function(tip)
      tip:SetText(def.tip[1], 1, 1, 1)
      tip:AddLine(def.tip[2], 1, 1, 1, true)
    end,
  }
end

-- Build(window, runButton, onTile, top): the banner and the tiles under the
-- title bar; returns the y offset below them
function Overview.Build(window, runButton, onTile, top)
  local o = { ctx = {} }
  o.banner = BuildBanner(window, runButton)
  o.banner:SetPoint("TOPLEFT", window, "TOPLEFT", 12, top)
  o.banner:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, top)
  local y = top - Overview.BANNER_H - GAP
  local tiles = {}
  for i, def in ipairs(Overview.TILES) do tiles[i] = StatTile(def) end
  o.grid = CobySuite_CobysLootSweeper.UI.CreateStatTiles(window, {
    tiles = tiles, columns = #tiles, minTileWidth = 100, height = Overview.TILE_H, context = o.ctx,
    selected = function() return o.current end,
    onClick = function(key)
      PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
      onTile(key)
    end,
  })
  o.grid:SetPoint("TOPLEFT", window, "TOPLEFT", 12, y)
  o.grid:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, y)
  o.tiles = o.grid.Tiles   -- Verify's tooltip grid reads them
  Overview.frames = o
  return y - Overview.TILE_H - GAP
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

function Overview.Paint(model, currentTab)
  local o = Overview.frames
  if not o then return end
  PaintBanner(model.banner)
  o.ctx.tiles = model.tiles
  o.current = currentTab
  o.grid:Refresh()
end
