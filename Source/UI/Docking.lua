-------------------------------------------------------------------------------
-- Docking: at the auction house the window opens beside it when items are
-- worth posting (showAtAuctionHouse); at a vendor it opens only from the
-- Loot Sweeper button on the vendor window (VendorButton). Either way it
-- closes with the window it sits beside. Only our own frame is anchored;
-- nothing of Blizzard's is shown, hidden or changed.
-------------------------------------------------------------------------------
local Events = CobysLootSweeper.Events
local Config = CobysLootSweeper.Config

local function Summary() return CobysLootSweeper.Pile.Summary() end

local function OnMerchant(isOpen)
  local UIModule = CobysLootSweeper.UI
  local merchant = _G.MerchantFrame
  if not merchant then return end
  if not isOpen then return UIModule.CloseIfDocked(merchant) end
end

local function OnAuction(isOpen)
  local UIModule = CobysLootSweeper.UI
  local auction = _G.AuctionHouseFrame
  if not auction then return end
  if not isOpen then return UIModule.CloseIfDocked(auction) end
  if not Config.Get("showAtAuctionHouse") then return end
  if Summary().post.count == 0 then return end
  UIModule.OpenDocked(auction, "post")
end

local listener = {}
function listener:ReceiveEvent(_, kind, isOpen)
  if kind == "merchant" then
    OnMerchant(isOpen)
  elseif kind == "auction" then
    OnAuction(isOpen)
  end
end
CobysLootSweeper.EventBus:Register(listener, { Events.InteractionChanged })
