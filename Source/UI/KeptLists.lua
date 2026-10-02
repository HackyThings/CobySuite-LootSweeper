-------------------------------------------------------------------------------
-- KeptLists: the settings window's "Your lists" page (Prefs' lists), built
-- from the suite's styled rows (KeptLists.Build, Config/Window.lua)
--
-- Whose lists (a read-only status, and "Change sharing..." opening the
-- Share or Split dialog, which takes effect when confirmed and drops the
-- page's unsaved edits first: sharing changes whose lists they apply to),
-- Copy another character's lists (a dropdown with counts and "Add to my
-- lists"), then the kept items, the remembered Sell choices and the places
-- never tracked, each with a remove x. Removing and importing are
-- staged edits (KeptLists.KEY, text Prefs.ApplyEdits reads): a staged
-- removal shows struck through with Undo, Apply keeps the edits and Cancel
-- drops them; Defaults stages nothing.
-------------------------------------------------------------------------------
local KeptLists = {}
CobysLootSweeper.KeptLists = KeptLists

local Prefs = CobysLootSweeper.Prefs
local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI

KeptLists.KEY = "keptEdits"

local ICONS = {
  mine = "Interface\\Icons\\INV_Misc_GroupLooking", shared = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  copy = "Interface\\Icons\\INV_Scroll_03", keep = "Interface\\Icons\\INV_Shield_06",
  sell = "Interface\\Icons\\INV_Misc_Coin_02", places = "Interface\\Icons\\INV_Misc_Map_01",
  instances = "Interface\\Icons\\INV_Misc_Key_03", zones = "Interface\\Icons\\INV_Misc_Map_01",
  delves = "Interface\\Icons\\INV_Misc_Map_01", quests = "Interface\\Icons\\INV_Misc_Note_01",
}
local PLACE_TAGS = { instances = "Dungeon or raid", zones = "Zone", delves = "Delve", quests = "Quest",
  allowed = "Current content" }
local PLACE_LISTS = { instances = true, zones = true, delves = true, quests = true }

-- The page's own config: the staged value is the list of edits; Get is
-- always "" (nothing pending), so Defaults ("") stages nothing
KeptLists.Config = {
  Get = function() return "" end,
  Set = function(_, edits) return Prefs.ApplyEdits(edits) end,
  Defaults = { [KeptLists.KEY] = "" },
}

-------------------------------------------------------------------------------
-- What the lists show
-------------------------------------------------------------------------------
local function ItemLabel(id, label)
  if type(label) == "string" then return label end
  local name = C_Item.GetItemNameByID(id)
  return name or ("Item " .. id)
end

local function PlaceLabel(list, id, label)
  if type(label) == "string" then return label end
  if list == "allowed" then return "Instance #" .. id end
  if list == "zones" then
    local info = C_Map.GetMapInfo(id)
    if info and info.name then return info.name end
  end
  return "#" .. id
end

local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function RemovedSet(edits)
  local removed = {}
  for _, e in ipairs(Prefs.ParseEdits(edits)) do
    if e.op == "remove" then removed[e.list .. ":" .. tostring(e.id)] = true end
  end
  return removed
end

-- Rows(edits, which): the saved entries of one group ("keep", "sell" or
-- "places"), by name; a staged removal stays, marked removed
function KeptLists.Rows(edits, which)
  local removed = RemovedSet(edits)
  local rows = {}
  for _, entry in ipairs(Prefs.Entries()) do
    local place = PLACE_LISTS[entry.list]
    if (which == "places" and place) or entry.list == which then
      local row = { list = entry.list, id = entry.id, removed = removed[entry.list .. ":" .. entry.id] == true }
      if place or entry.list == "allowed" then
        row.text = PlaceLabel(entry.list, entry.id, entry.label)
        row.tag, row.icon = PLACE_TAGS[entry.list], ICONS[entry.list] or ICONS.places
      else
        row.itemID = entry.id
        row.text = ItemLabel(entry.id, entry.label)
      end
      rows[#rows + 1] = row
    end
  end
  table.sort(rows, function(a, b)
    if a.list ~= b.list then return a.list < b.list end
    return Plain(a.text) < Plain(b.text)
  end)
  return rows
end

-- How many entries of a group stay once the staged removals are applied
function KeptLists.Count(edits, which)
  local removed = RemovedSet(edits)
  local n = 0
  for _, entry in ipairs(Prefs.Entries()) do
    local inGroup = (which == "places" and PLACE_LISTS[entry.list]) or entry.list == which
    if inGroup and not removed[entry.list .. ":" .. entry.id] then n = n + 1 end
  end
  return n
end

-- WithoutEdit(edits, ...): the edit list less that one edit (Undo)
function KeptLists.WithoutEdit(edits, ...)
  local line = table.concat({ ... }, "\t")
  local kept = {}
  for each in tostring(edits or ""):gmatch("[^\n]+") do
    if each ~= line then kept[#kept + 1] = each end
  end
  return table.concat(kept, "\n")
end

-- The staged imports, as a line for the note
function KeptLists.ImportNote(edits)
  local names = {}
  for _, e in ipairs(Prefs.ParseEdits(edits)) do
    if e.op == "import" then
      local lists = COBYS_LOOT_SWEEPER_PREFS.chars[e.from]
      names[#names + 1] = lists and lists.name or e.from
    end
  end
  if #names == 0 then return nil end
  return "Importing from " .. table.concat(names, ", ") .. ": press Apply to keep it, or Cancel."
end

-- "12 kept items, 3 Sells and 2 blocked places"
function KeptLists.CountText(c)
  local parts = {}
  local function Add(n, one, many) if n > 0 then parts[#parts + 1] = n .. " " .. (n == 1 and one or many) end end
  Add(c.keep, "kept item", "kept items")
  Add(c.sell, "Sell", "Sells")
  Add(c.blocked, "blocked place", "blocked places")
  if #parts == 0 then return "nothing new" end
  if #parts == 1 then return parts[1] end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- "Thrall - Illidan (12 kept, 2 blocked)"
function KeptLists.CharacterLabel(c)
  local parts = {}
  if c.counts.keep > 0 then parts[#parts + 1] = c.counts.keep .. " kept" end
  if c.counts.sell > 0 then parts[#parts + 1] = c.counts.sell .. " sold" end
  if c.counts.blocked > 0 then parts[#parts + 1] = c.counts.blocked .. " blocked" end
  if #parts == 0 then return c.name .. " (empty)" end
  return c.name .. " (" .. table.concat(parts, ", ") .. ")"
end

-------------------------------------------------------------------------------
-- The share and split dialogs (the "Whose lists" tiles open them)
-------------------------------------------------------------------------------
local shareDialog, splitDialog

local function After(window)
  if not window then return end
  window:Unstage(KeptLists.KEY)
  window:Sync()
end

-- Per character -> shared: whose lists everyone gets
local function OpenShare(window)
  if not shareDialog then
    shareDialog = UI.CreateDialogPopup({
      name = "CobysLootSweeperShareListsPopup", title = "Share one set of lists?", width = 420, height = 210,
      icon = CobysLootSweeper.ICON,
      hidden = true, confirmText = "Share", cancelText = "Cancel",
      body = "Every character will use the same kept items, Sells and blocked places, as soon as you press Share. Unsaved removals and imports on this page are dropped. Whose lists should they share?",
      onConfirm = function(popup)
        Prefs.UseAccountWide(popup.Pick:GetValue())
        After(popup.window)
      end,
    })
    shareDialog.Pick = UI.CreateDropDown(shareDialog, {
      label = false, width = 240, point = { "TOP", shareDialog, "TOP", 0, -118 },
    })
  end
  shareDialog.window = window
  local me, myName = Prefs.CharKey()
  local labels, values = { (myName or "This character") .. " (this character)" }, { me }
  for _, c in ipairs(Prefs.OtherCharacters()) do
    labels[#labels + 1] = c.name
    values[#values + 1] = c.key
  end
  shareDialog.Pick:InitAgain(labels, values)
  shareDialog.Pick:SetValue(me)
  shareDialog:Show()
end

-- Shared -> per character: everyone starts with a copy, or empty
local function OpenSplit(window)
  if not splitDialog then
    splitDialog = UI.CreateDialogPopup({
      name = "CobysLootSweeperSplitListsPopup", title = "Give each character its own lists?", width = 440, height = 170,
      icon = CobysLootSweeper.ICON,
      hidden = true, confirmText = "Copy to every character", cancelText = "Cancel",
      body = "Each character can start with a copy of the shared lists, or with empty lists. It happens as soon as you choose; unsaved removals and imports on this page are dropped.",
      onConfirm = function(popup)
        Prefs.UsePerCharacter(true)
        After(popup.window)
      end,
    })
    -- Copy at the bottom-left (the dialog's confirm), Start empty beside
    -- it, Cancel where the dialog puts it, at the bottom-right
    splitDialog.ConfirmButton:SetWidth(170)
    splitDialog.Empty = UI.CreateButton(splitDialog, {
      text = "Start empty", size = { 110, U.ButtonSize.MEDIUM.height }, point = { "LEFT", splitDialog.ConfirmButton, "RIGHT", 8, 0 },
      onClick = function()
        splitDialog:Hide()
        Prefs.UsePerCharacter(false)
        After(splitDialog.window)
      end,
    })
  end
  splitDialog.window = window
  splitDialog:Show()
end

-- For Source/Tests/Verify's dialog scenes
KeptLists._test = { OpenShare = OpenShare, OpenSplit = OpenSplit }

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
local function Stage(window, edits) window:Stage(KeptLists.KEY, edits) end

local function List(panel, which, fields)
  local spec = {
    rows = function(window)
      local rows = KeptLists.Rows(window:Get(KeptLists.KEY), which)
      for _, row in ipairs(rows) do
        row.tooltip = row.removed and "Leaves the list when you press Apply." or nil
      end
      return rows
    end,
    onRemove = function(entry, window)
      Stage(window, Prefs.AddEdit(window:Get(KeptLists.KEY), "remove", entry.list, entry.id))
    end,
    onUndo = function(entry, window)
      Stage(window, KeptLists.WithoutEdit(window:Get(KeptLists.KEY), "remove", entry.list, entry.id))
    end,
    searchAt = 20,
  }
  for k, v in pairs(fields) do spec[k] = v end
  panel:List(spec)
end

local function PerCharacter() return not Prefs.IsAccountWide() end

-- Build(panel): the page's rows
function KeptLists.Build(panel)
  -- Registers the page's one staged setting with its config
  panel:Custom{ height = 0, keys = { KeptLists.KEY } }

  panel:Section("Whose lists", { icon = ICONS.mine })
  panel:StatusCard{
    icon = function() return Prefs.IsAccountWide() and ICONS.shared or ICONS.mine end,
    state = "ok",
    stateText = function() return Prefs.IsAccountWide() and "Shared" or "Per character" end,
    title = function() return Prefs.IsAccountWide() and "Shared by all your characters" or "Just this character" end,
    description = function()
      local mode
      if Prefs.IsAccountWide() then
        mode = "Every character uses one set of kept items, Sells and blocked places."
      else
        local _, name = Prefs.CharKey()
        mode = string.format("%s keeps its own kept items, Sells and blocked places.", name or "This character")
      end
      return mode .. " Changing this takes effect as soon as you confirm, not with Apply."
    end,
    actions = {
      { text = "Change sharing...", width = 160,
        tooltip = "Share one set of lists with every character, or give each character its own again.",
        onClick = function(window)
          if Prefs.IsAccountWide() then OpenSplit(window) else OpenShare(window) end
        end },
    },
  }

  panel:Section("Copy another character's lists", { icon = ICONS.copy, visibleWhen = PerCharacter })
  panel:DropdownAction{
    visibleWhen = PerCharacter,
    label = "Character",
    options = function()
      local labels, values = {}, {}
      for _, c in ipairs(Prefs.OtherCharacters()) do
        labels[#labels + 1] = KeptLists.CharacterLabel(c)
        values[#values + 1] = c.key
      end
      return labels, values
    end,
    detail = function(key)
      if not key then return "" end
      return "Adds " .. KeptLists.CountText(Prefs.ImportCounts(key)) .. ". Keep choices replace matching Sell choices. Other entries stay."
    end,
    buttonText = "Add to my lists",
    buttonTooltip = "Adds their kept items, Sells and blocked places to yours when you press Apply.",
    onClick = function(key, window)
      if key then Stage(window, Prefs.AddEdit(window:Get(KeptLists.KEY), "import", key)) end
    end,
    emptyText = "No other character has lists yet. Log in on one with Loot Sweeper first.",
  }

  panel:Section("Kept items", { icon = ICONS.keep,
    count = function(window) return KeptLists.Count(window:Get(KeptLists.KEY), "keep") end })
  List(panel, "keep", {
    removeTooltip = "Stop keeping it: Loot Sweeper may list future copies again.",
    empty = { title = "Nothing kept yet", text = "Right-click an item in the Loot Sweeper window and choose Keep.",
              icon = ICONS.keep },
  })

  panel:Section("Remembered Sell choices", { icon = ICONS.sell, subtitle = "Other protections still apply.",
    count = function(window) return KeptLists.Count(window:Get(KeptLists.KEY), "sell") end })
  List(panel, "sell", {
    removeTooltip = "Forget the remembered Sell: future copies are sorted as usual.",
    empty = { title = "No remembered Sell choices",
              text = "Right-click an item, tick Remember Sell for future copies, then choose Sell.", icon = ICONS.sell },
  })

  panel:Section("Places never tracked", { icon = ICONS.places,
    count = function(window) return KeptLists.Count(window:Get(KeptLists.KEY), "places") end })
  List(panel, "places", {
    removeTooltip = "Track it again from your next visit.",
    empty = { title = "No blocked places",
              text = "Right-click the Loot Sweeper window's banner and choose Never track here, or type /ls block.",
              icon = ICONS.places },
  })

  panel:Section("Places always tracked", { icon = ICONS.places, subtitle = "Current content you said Yes, always here to.",
    count = function(window) return KeptLists.Count(window:Get(KeptLists.KEY), "allowed") end })
  List(panel, "allowed", {
    removeTooltip = "Ask again next time instead of tracking it by itself.",
    empty = { title = "No current content tracked always",
              text = "In this season's dungeons, raids and delves, click [Track this run] in chat and choose Yes, always here.",
              icon = ICONS.places },
  })

  panel:Note{
    visibleWhen = function(get) return (get(KeptLists.KEY) or "") ~= "" end,
    text = function(window)
      return KeptLists.ImportNote(window:Get(KeptLists.KEY)) or "Removals take effect when you press Apply."
    end,
  }
end
