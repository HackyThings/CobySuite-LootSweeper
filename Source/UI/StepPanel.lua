-------------------------------------------------------------------------------
-- StepPanel: one item at a time, for what the player judges item by item
-- (tradeable and warbound loot) or the game wants a click for each (deleting)
--
-- Open(mode, rows, title, note): mode "sell" (at a vendor) or "delete";
-- note, the orange line under a sale (why it might be worth skipping). The panel
-- shows which item of how many, its icon and name in its quality's color,
-- what it is worth or why, and three buttons: Sell or Delete, Skip and Stop.
-- Each click acts on that one item after checking it again: the same GUID
-- in a carried bag, the stack size still the one shown, still wholly run
-- loot (Ledger.IsSellable), not locked,
-- no combat, and still Vendor (selling, through Seller.Start, which also
-- needs the vendor open) or still deletable (Rules.Deletable). The panel
-- moves on once the item has left the bags.
--
-- Deleting: ClearCursor, pick the item up, check the cursor holds that very
-- item, DeleteCursorItem(). The game allows that only inside a click, so
-- every delete is the player's own click on Delete; nothing is deleted by
-- itself. A delete is permanent (no buyback), which the panel says.
-------------------------------------------------------------------------------
local StepPanel = {}
CobysLootSweeper.StepPanel = StepPanel

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI
local Utilities = CobysLootSweeper.Utilities

StepPanel.WAIT = 2.0
StepPanel.POLL = 0.1

local WIDTH, HEIGHT, PAD = 420, 220, 16

local seams = {
  InCombat = function() return InCombatLockdown() end,
  Now = function() return GetTime() end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  Locate = function(guid) return CobysLootSweeper.Bags.Locate(guid) end,
  ClearCursor = function() ClearCursor() end,
  Pickup = function(bag, slot) C_Container.PickupContainerItem(bag, slot) end,
  CursorItemID = function()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" then return nil end
    return itemID
  end,
  DeleteCursor = function() DeleteCursorItem() end,
}
StepPanel._test = { seams = seams }

local panel
local session = nil   -- { mode, rows, index, done, skipped, busy, title, note }

local function Debug() return CobysLootSweeper.Debug end

local function Current() return session and session.rows[session.index] end

-------------------------------------------------------------------------------
-- Checks
-------------------------------------------------------------------------------
-- The row as it is now: bag, slot, or nil and why it can't be acted on
function StepPanel.Verify(mode, row)
  if seams.InCombat() then return nil, "combat" end
  local bag, slot, info = seams.Locate(row.guid)
  if not bag then return nil, "gone" end
  if info.itemID ~= row.entry.itemID then return nil, "changed" end
  -- The stack must be the size the player is looking at (UI-02): a changed
  -- one is shown again and needs another press
  if row.facts and type(row.facts.count) == "number" and info.stackCount ~= row.facts.count then
    row.facts.count = info.stackCount
    return nil, "count"
  end
  if info.isLocked then return nil, "locked" end
  local ledger = CobysLootSweeper.Runs.Ledger()
  if not CobysLootSweeper.Ledger.IsSellable(ledger, row.guid, info.stackCount) then return nil, "not run loot" end
  if mode == "delete" then
    local entry = ledger.pile[row.guid]
    local facts = CobysLootSweeper.Facts.Read(bag, slot, info)
    if not facts then return nil, "unreadable" end
    local pref = CobysLootSweeper.Prefs.For(entry)
    if not CobysLootSweeper.Rules.Deletable(entry, facts, pref, CobysLootSweeper.Rules.Settings()) then
      return nil, "protected"
    end
  end
  return bag, slot
end

local SKIP_TEXT = {
  combat = "Not in combat. Try again once it ends.",
  gone = "It isn't in your bags any more.",
  changed = "That bag slot holds something else now.",
  locked = "The game is busy with it. Try again in a moment.",
  count = "The stack's size changed. Check the new count, then press again.",
  ["not run loot"] = "Loot Sweeper can't be sure all of this stack came from a run.",
  unreadable = "The game hasn't loaded this item yet.",
  protected = "Something now protects this item, so it stays.",
}

-------------------------------------------------------------------------------
-- Painting
-------------------------------------------------------------------------------
local function QualityHex(quality)
  local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  return c and c.hex or "|cffffffff"
end

local function Paint(note)
  if not panel or not session then return end
  local row = Current()
  local total = #session.rows
  if not row then
    panel.Progress:SetText("All done")
    panel.Icon:SetTexture(CobysLootSweeper.ICON)
    panel.Name:SetText(session.title)
    local verb = session.mode == "delete" and "Deleted" or "Sold"
    panel.Detail:SetText(string.format("%s %d, skipped %d.", verb, session.done, session.skipped))
    panel.Warning:SetText("")
    panel.Action:Hide()
    panel.Skip:Hide()
    panel.Stop:SetText("Close")
    return
  end
  local facts = row.facts
  panel.Progress:SetText(string.format("%s: item %d of %d", session.title, session.index, total))
  panel.Icon:SetTexture(facts.icon or 134400)
  local count = facts.count or 1
  panel.Name:SetText(QualityHex(facts.quality) .. (facts.name or "Item") .. "|r" .. (count > 1 and (" x" .. count) or ""))
  if session.mode == "delete" then
    panel.Detail:SetText(row.reason or "No vendor buys this.")
    panel.Warning:SetText("Deleting is permanent. There is no buyback.")
    panel.Action:SetText("Delete")
  else
    local ah = row.ahValue and (", about " .. Utilities.Money(row.ahValue) .. " on the AH") or ""
    panel.Detail:SetText(string.format("A vendor pays %s%s.", Utilities.Money(row.vendorValue or 0), ah))
    panel.Warning:SetText(session.note or "")
    panel.Action:SetText("Sell")
  end
  if note then panel.Warning:SetText(note) end
  panel.Action:Show()
  panel.Skip:Show()
  panel.Stop:SetText("Stop")
  local ready = not session.busy and not seams.InCombat()
    and (session.mode ~= "sell" or CobysLootSweeper.Seller.MerchantReady())
  panel.Action:SetEnabled(ready)
  panel.Skip:SetEnabled(not session.busy)
end

-- s: the session the action began in; a callback for any other (the panel
-- closed or reopened since) changes nothing here (UI-03)
local function Advance(acted, s)
  if not session or (s and s ~= session) then return end
  session.busy = false
  if acted then session.done = session.done + 1 else session.skipped = session.skipped + 1 end
  session.index = session.index + 1
  Paint()
end

-------------------------------------------------------------------------------
-- Acting
-------------------------------------------------------------------------------
-- Waits for the GUID to leave the bags; false after StepPanel.WAIT
local function AwaitGone(guid, deadline, done)
  if not seams.Locate(guid) then return done(true) end
  if seams.Now() >= deadline then return done(false) end
  seams.After(StepPanel.POLL, function() AwaitGone(guid, deadline, done) end)
end

function StepPanel.DeleteCurrent()
  local row = Current()
  if not row or session.busy then return false end
  local bag, slot = StepPanel.Verify("delete", row)
  if not bag then
    Paint(SKIP_TEXT[slot] or "It can't be deleted now.")
    return false
  end
  session.busy = true
  pcall(seams.ClearCursor)
  pcall(seams.Pickup, bag, slot)
  local ok, onCursor = pcall(seams.CursorItemID)
  if not ok or onCursor ~= row.entry.itemID then
    pcall(seams.ClearCursor)
    session.busy = false
    Paint("The game didn't pick that item up. Nothing was deleted.")
    return false
  end
  pcall(seams.DeleteCursor)
  Paint()
  local guid, began = row.guid, session
  AwaitGone(guid, seams.Now() + StepPanel.WAIT, function(gone)
    if gone then
      -- The delete happened whatever became of the panel
      CobysLootSweeper.History.Deleted(guid)
      Debug().Log("SELL", "Deleted %s", tostring(row.facts.name))
      Advance(true, began)
    else
      pcall(seams.ClearCursor)
      if session ~= began then return end
      session.busy = false
      Paint("The game didn't delete it. Nothing changed.")
    end
  end)
  return true
end

function StepPanel.SellCurrent()
  local row = Current()
  if not row or session.busy then return false end
  local bag, why = StepPanel.Verify("sell", row)
  if not bag then
    Paint(SKIP_TEXT[why] or "It can't be sold now.")
    return false
  end
  session.busy = true
  Paint()
  local began = session
  local started = CobysLootSweeper.Seller.Start({ row }, { onFinish = function(state)
    if session ~= began then return end
    if state.sold > 0 then
      Advance(true, began)
    else
      session.busy = false
      Paint(state.message or "It didn't sell.")
    end
  end })
  if not started then
    session.busy = false
    Paint("Selling needs the vendor open and no combat.")
  end
  return started
end

local function OnAction()
  if not session then return end
  if session.mode == "delete" then StepPanel.DeleteCurrent() else StepPanel.SellCurrent() end
end

function StepPanel.Skip()
  if not session or session.busy then return end
  Advance(false)
end

function StepPanel.Close()
  session = nil
  if panel then panel:Hide() end
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------
local function Build()
  if panel or seams.InCombat() then return end
  panel = UI.CreateWindow({
    name = "CobysLootSweeperStepPanel", title = "Coby's Loot Sweeper", icon = CobysLootSweeper.ICON,
    width = WIDTH, height = HEIGHT, strata = "DIALOG", escapeCloses = true,
    point = { "CENTER", UIParent, "CENTER", 0, 140 },
  })
  panel.Progress = panel:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  panel.Progress:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -34)
  panel.Progress:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.Progress:SetJustifyH("LEFT")
  local gray = U.Colors.LABEL_GRAY
  panel.Progress:SetTextColor(gray[1], gray[2], gray[3])
  panel.Icon = panel:CreateTexture(nil, "ARTWORK")
  panel.Icon:SetSize(44, 44)
  panel.Icon:SetPoint("TOPLEFT", panel.Progress, "BOTTOMLEFT", 0, -10)
  panel.Name = panel:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  panel.Name:SetPoint("TOPLEFT", panel.Icon, "TOPRIGHT", 10, -2)
  panel.Name:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.Name:SetJustifyH("LEFT")
  panel.Name:SetWordWrap(false)
  panel.Detail = panel:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  panel.Detail:SetPoint("TOPLEFT", panel.Name, "BOTTOMLEFT", 0, -6)
  panel.Detail:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.Detail:SetJustifyH("LEFT")
  panel.Warning = panel:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  panel.Warning:SetPoint("TOPLEFT", panel.Icon, "BOTTOMLEFT", 0, -12)
  panel.Warning:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
  panel.Warning:SetJustifyH("LEFT")
  panel.Warning:SetWordWrap(true)
  local warn = U.Colors.CAUTION_ORANGE
  panel.Warning:SetTextColor(warn[1], warn[2], warn[3])
  local h = U.ButtonSize.MEDIUM.height
  panel.Action = UI.CreateButton(panel, { text = "Sell", size = { 110, h },
    point = { "BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 14 }, onClick = OnAction })
  panel.Skip = UI.CreateButton(panel, { text = "Skip", size = { 90, h },
    point = { "LEFT", panel.Action, "RIGHT", 8, 0 }, onClick = function() StepPanel.Skip() end,
    tooltip = "Leave this one in your bags and go to the next." })
  panel.Stop = UI.CreateButton(panel, { text = "Stop", size = { 90, h },
    point = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 14 }, onClick = function() StepPanel.Close() end,
    tooltip = "Close this panel. Everything not done yet stays in your bags." })
  panel:HookScript("OnHide", function() session = nil end)
  panel:Hide()
  StepPanel.panel = panel
end

-- Open(mode, rows, title, note): false when there is nothing to step through or
-- the panel can't be built now (combat)
function StepPanel.Open(mode, rows, title, note)
  if not rows or #rows == 0 then return false end
  Build()
  if not panel then return false end
  session = { mode = mode, rows = rows, index = 1, done = 0, skipped = 0, title = title or "Loot Sweeper", note = note }
  panel:Show()
  Paint()
  return true
end

function StepPanel._test.Session() return session end

-- Repaint when the vendor, combat or the seller changes what can be done
local listener = {}
function listener:ReceiveEvent()
  if session and not session.busy then Paint() end
end
CobysLootSweeper.EventBus:Register(listener, { CobysLootSweeper.Events.InteractionChanged, CobysLootSweeper.Events.SellChanged })

EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", Build)
