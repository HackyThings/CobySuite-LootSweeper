-------------------------------------------------------------------------------
-- TrackOffer: how current content is offered (Runs.CheckOffer decides when)
--
-- Announce(info): a few seconds after the loading screen (Runs.OFFER_DELAY,
-- past the burst of chat that follows it), one chat line with the addon's
-- icon and a [Track this run] link, a toast near the top of the screen
-- (the shared CobySuite.UI.NewToast; click it to choose) and a chirp.
-- Open(id): the suite's prompt (CobySuite.UI.CreateClickPrompt: title bar
-- with the addon icon, a close X, movable, Escape closes it): Yes, always
-- here / Yes, this time / No. Closing it answers nothing; the link or the
-- toast opens it again while the offer stands.
--
-- The link is an "addon" hyperlink (|Haddon:CobysLootSweeper:track:<id>|h).
-- The game hands a click on such a link to EventRegistry's "SetItemRef"
-- callbacks (Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua), so
-- Loot Sweeper only registers a callback and replaces nothing of
-- Blizzard's. The prompt is built out of combat (at load, or when combat
-- ends); toasts are only shown out of combat (they make frames).
-------------------------------------------------------------------------------
local TrackOffer = {}
CobysLootSweeper.TrackOffer = TrackOffer

local U = CobySuite_CobysLootSweeper.Utilities
local UI = CobySuite_CobysLootSweeper.UI

TrackOffer.TOAST_SECONDS = 20

local prompt, toast

local seams = {
  Listen = function(fn) EventRegistry:RegisterCallback("SetItemRef", fn, TrackOffer) end,
  Chirp = function() PlaySound(SOUNDKIT.UI_BNET_TOAST) end,
  InCombat = function() return InCombatLockdown() end,
}

-- Parse(link): the instance map ID in one of Loot Sweeper's track links
function TrackOffer.Parse(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("addon:CobysLootSweeper:track:(%d+)"))
end

-- The answer is for the offer the prompt showed, never one that replaced it
-- (review 2026-10-01, UI-02)
local shown = nil

local function Answer(answer)
  if prompt then prompt:Hide() end
  local offer = shown
  shown = nil
  CobysLootSweeper.Runs.AnswerOffer(answer, offer)
end

local function Build()
  if prompt or seams.InCombat() then return end
  prompt = UI.CreateClickPrompt({
    name = "CobysLootSweeperTrackOfferPrompt", title = "Track this run?", icon = CobysLootSweeper.ICON,
    width = 440,
    buttons = {
      { key = "Always", text = "Yes, always here", onClick = function() Answer("always") end },
      { key = "Once", text = "Yes, this time", width = 120, onClick = function() Answer("once") end },
      { key = "No", text = "No", width = 90, side = "right", onClick = function() Answer("no") end },
    },
  })
  toast = UI.NewToast({
    maxVisible = 1, width = 320, height = 50, defaultDuration = TrackOffer.TOAST_SECONDS,
    defaultAccentColor = U.Colors.STATUS_GOLD,
    position = function(t) t:SetPoint("TOP", UIParent, "TOP", 0, -150) end,
  })
end

-- Open(id): the prompt for the offer still open here
function TrackOffer.Open(id)
  Build()
  if not prompt then
    CobysLootSweeper.Utilities.Message("The Track this run prompt opens when combat ends.")
    U.RunOutOfCombat(function() TrackOffer.Open(id) end, "CobysLootSweeperTrackOffer")
    return false
  end
  local offer = CobysLootSweeper.Runs.OpenOffer(id)
  if not offer then
    CobysLootSweeper.Utilities.Message("That offer has run out. Loot Sweeper offers again when you next enter current content.")
    return false
  end
  shown = offer
  prompt:Ask(string.format(
    "Track %s like old content? Only the loot from this run can be sold, and gear near what you wear stays protected.\n\nYes, always here remembers it under Your lists, and it then starts by itself.",
    offer.name or "this place"))
  return true
end

-- Announce(info): the toast and the chirp beside the chat line (Runs)
function TrackOffer.Announce(info)
  seams.Chirp()
  Build()
  if not toast or seams.InCombat() then return end
  local id = info.instanceMapID
  toast.Show({
    title = "Track this run?",
    message = string.format("%s is this season's content. Click to choose.", info.name or "This place"),
    icon = CobysLootSweeper.ICON,
    onClick = function() TrackOffer.Open(id) end,
  })
end

local function OnLink(_, link)
  local id = TrackOffer.Parse(link)
  if id then TrackOffer.Open(id) end
end
TrackOffer._test = { seams = seams, OnLink = OnLink }
-- Is the prompt up? (Verify's postconditions)
function TrackOffer._test.PromptShown() return prompt ~= nil and prompt:IsShown() end

EventUtil.ContinueOnAddOnLoaded("CobysLootSweeper", function()
  local ok, err = pcall(seams.Listen, OnLink)
  if not ok then CobysLootSweeper.Debug.Log("UI", "The Track this run link can't be listened for: %s", tostring(err)) end
  C_Timer.After(0, Build)
end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function() Build() end)
