-------------------------------------------------------------------------------
-- Ledger: which items in the bags came from a run (pure logic, no client calls)
--
-- The ledger follows items by GUID from one complete inventory read to the
-- next. A read is every occupied bag slot plus the equipped items:
--   read.items[guid] = { itemID, count, link, place = "bag" | "equip", openable }
--   read.owned[itemID] = the character's total of that item (bags, bank,
--                        warband bank, reagent bank), for every item ID in the
--                        read and in the last one
--
-- State (kept per character by Runs):
--   state.known[guid] = { itemID, count, place, openable }   the last read
--   state.owned[itemID] = total at the last read
--   state.pile[guid]    = { itemID, link, count, added, hold, runId, at, pref, fromToken }
--     count  units proven to be run loot (the whole stack when hold is nil)
--     added  run units mixed into a stack that also holds other items
--     hold   nil (sellable when the rules allow), "mixed" or "interrupted"
--   state.away[guid]    = a pile entry that left the bags with no window open
--                         to explain it, plus awayAt (see below)
--   state.gone[guid]    = { itemID, count, at }: one of the player's own bag
--                         items that left with no window open (see below)
--   state.container = nil, or an open container session (below)
--
-- The rules (design sections 4 and 5):
--   * An arrival is a new GUID, or a stack growing, while a run is active.
--     It counts only when the item's owned total rose by at least as much
--     (the "allowance"); a withdrawal from the bank or unequipping an item
--     never raises the total, so it never looks like loot.
--   * While a fence is up (mailbox, vendor, trade, AH, bank, quest reward,
--     crafting) the allowance is zero: nothing arriving joins the pile.
--   * Units leaving a pure claimed stack without leaving the character go to
--     a per-item pool; a new stack or a claimed stack's growth covered by the
--     pool keeps its claim (a split or a merge of run loot), and a Keep choice
--     on the units goes with them. Units that left the character are taken
--     out of the pool first, so an unexplained drop never keeps a selling
--     allowance alive. The pool moves nothing while a fence is up (a bank or
--     mail swap can keep the total the same).
--   * A new stack counted as loot by the total alone is held as mixed when
--     the player carries another stack of that item that isn't run loot: it
--     could be split from theirs.
--   * A claimed stack that grows with no explanation, or run loot landing on
--     a stack that was already there, becomes "mixed": kept, never sold.
--   * An equipped item, or one that leaves the bags while a window is open
--     (vendor, bank, mail, trade), is released for good. One that leaves with
--     nothing open to explain it goes "away" (a destroy, or a zone that hides
--     the bags: entering Arcantina hid a whole run's loot, owned totals and
--     all, twice on 2026-09-30): hidden, and back in the pile as it was if
--     the same GUID turns up again, so a zone never loses a run's loot. Only
--     a departure whose units another stack took this read (a split or a
--     merge) is released. Away entries are dropped after Ledger.AWAY_DAYS.
--   * ClaimConversion(state, read, before, conv): a token of a run that the
--     player used from Loot Sweeper (conv: its GUID, item, run, loot time):
--     once the token has left the bags, the one new bag item whose owned
--     total rose since the read before joins the token's run as if looted
--     with the token; with several such items none is claimed.
--   * The player's own bag items that leave with nothing open are kept in
--     state.gone (Ledger.AWAY_DAYS, at most Ledger.GONE_MAX): one coming back
--     under the same GUID is known, not new, and its units never count as
--     loot (a zone that hides the bags during a manual run must not turn the
--     player's own items into loot; review 2026-09-30, TRACK-04).
--   * Rescue(state, read, records): run loot the history knows (looted,
--     never sold) that is in the bags but in neither the pile nor away
--     rejoins the pile, held when its stack size changed.
--   * The first read after login or /reload is a resync: no arrivals, and a
--     claim that can only be matched by quantity is held as "interrupted".
--   * Opening a container starts a session: what it yields waits, and joins
--     the pile at the end only if every container that was used up was run
--     loot (followed by GUID, so two boxes of one kind are told apart).
-------------------------------------------------------------------------------
local Ledger = {}
CobysLootSweeper.Ledger = Ledger

Ledger.HOLD_MIXED = "mixed"
Ledger.HOLD_INTERRUPTED = "interrupted"
Ledger.AWAY_DAYS = 14
Ledger.GONE_MAX = 1000

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
function Ledger.NewState()
  return { known = {}, owned = {}, pile = {}, away = {}, gone = {} }
end

-- Fills in any missing table so a damaged or older saved state can be used
function Ledger.Normalize(state)
  if type(state) ~= "table" then state = {} end
  if type(state.known) ~= "table" then state.known = {} end
  if type(state.owned) ~= "table" then state.owned = {} end
  if type(state.pile) ~= "table" then state.pile = {} end
  if type(state.away) ~= "table" then state.away = {} end
  if type(state.gone) ~= "table" then state.gone = {} end
  for guid, g in pairs(state.gone) do
    if type(guid) ~= "string" or type(g) ~= "table" or type(g.itemID) ~= "number" or type(g.count) ~= "number" then
      state.gone[guid] = nil
    end
  end
  for guid, entry in pairs(state.away) do
    if type(guid) ~= "string" or type(entry) ~= "table" or type(entry.itemID) ~= "number"
        or type(entry.count) ~= "number" or type(entry.added) ~= "number" then
      state.away[guid] = nil
    end
  end
  if state.container ~= nil and type(state.container) ~= "table" then state.container = nil end
  for guid, entry in pairs(state.pile) do
    if type(guid) ~= "string" or type(entry) ~= "table" or type(entry.itemID) ~= "number" then
      state.pile[guid] = nil
    else
      if type(entry.count) ~= "number" or entry.count < 0 then entry.count = 0 end
      if type(entry.added) ~= "number" or entry.added < 0 then entry.added = 0 end
      if entry.hold ~= nil and entry.hold ~= Ledger.HOLD_MIXED and entry.hold ~= Ledger.HOLD_INTERRUPTED then
        entry.hold = Ledger.HOLD_INTERRUPTED
      end
      if entry.count == 0 and entry.added == 0 then state.pile[guid] = nil end
    end
  end
  return state
end

-------------------------------------------------------------------------------
-- Pool helpers (units per item ID that may carry a claim to another stack)
-------------------------------------------------------------------------------
-- keep: the units came from a stack the player chose to keep; whatever
-- takes them keeps that choice (a split or merge never undoes a Keep)
-- shrink: the units came from a stack that is still there (a split), not
-- one that left; MarkAway spends takes on those first
local function PoolAdd(pool, itemID, units, runId, keep, shrink)
  if units <= 0 then return end
  local p = pool[itemID]
  if not p then
    p = { units = 0, runId = runId, shrink = 0 }
    pool[itemID] = p
  end
  p.units = p.units + units
  p.runId = p.runId or runId
  p.keep = p.keep or keep or nil
  if shrink then p.shrink = p.shrink + units end
end

-- Units for another stack: take, runId, keep. Never while a fence is up: a
-- bank, mail or trade window can swap a run stack for one of the player's
-- own with the same total, so quantity proves nothing there
local function PoolTake(pool, itemID, wanted, ctx)
  local p = pool[itemID]
  if not p or wanted <= 0 or ctx.fenced then return 0, nil, nil end
  local take = math.min(p.units, wanted)
  p.units = p.units - take
  p.taken = (p.taken or 0) + take   -- what another stack took (MarkAway)
  return take, p.runId, take > 0 and p.keep or nil
end

-- Allowance: how many units of an item may count as new loot this read
local function AllowanceTake(allow, itemID, wanted)
  local have = allow[itemID] or 0
  if have <= 0 or wanted <= 0 then return 0 end
  local take = math.min(have, wanted)
  allow[itemID] = have - take
  return take
end

-------------------------------------------------------------------------------
-- Changes (what the caller logs and shows)
-------------------------------------------------------------------------------
local function NewChanges()
  return { claimed = {}, released = {}, held = {}, pending = {}, away = {} }
end

local function Note(list, guid, itemID, units, why)
  list[#list + 1] = { guid = guid, itemID = itemID, units = units, why = why }
end

local function Release(state, changes, guid, why)
  local entry = state.pile[guid]
  if not entry then return end
  state.pile[guid] = nil
  Note(changes.released, guid, entry.itemID, entry.count + entry.added, why)
end

local function Hold(entry, changes, guid, hold)
  if entry.hold == hold or entry.hold == Ledger.HOLD_MIXED then return end
  entry.hold = hold
  Note(changes.held, guid, entry.itemID, entry.count + entry.added, hold)
end

-------------------------------------------------------------------------------
-- Step 1: allowance per item (how much the owned total rose)
-------------------------------------------------------------------------------
local function OwnedDeltas(state, read)
  local deltas = {}
  for itemID, now in pairs(read.owned or {}) do
    if type(itemID) == "number" and type(now) == "number" then
      deltas[itemID] = now - (state.owned[itemID] or 0)
    end
  end
  return deltas
end

local function BuildAllowance(deltas, ctx)
  local allow = {}
  local open = ctx.runActive and not ctx.fenced and not ctx.resync
  if not open then return allow end
  for itemID, delta in pairs(deltas) do
    if delta > 0 then allow[itemID] = delta end
  end
  return allow
end

-------------------------------------------------------------------------------
-- Step 2: items that left, and claimed units that left their stack
-------------------------------------------------------------------------------
local function IsPure(entry)
  return entry ~= nil and entry.hold == nil and entry.count > 0
end

-- A container used up or opened: which kind, for the container session
local function NoteContainerDrop(state, guid, known)
  local session = state.container
  if not session or not known.openable then return end
  if IsPure(state.pile[guid]) then
    session.claimedDrop = true
  else
    session.otherDrop = true
  end
end

-- departed: the pile entries that left this read with no window open, for
-- MarkAway once the arrivals have had their turn at the pool
local function CollectDepartures(state, read, pool, changes, ctx, departed)
  for guid, known in pairs(state.known) do
    local now = read.items[guid]
    if not now then
      NoteContainerDrop(state, guid, known)
      local entry = state.pile[guid]
      if IsPure(entry) then PoolAdd(pool, entry.itemID, entry.count, entry.runId, entry.pref == "keep") end
      if entry then
        state.pile[guid] = nil
        if ctx.fenced or known.place == "equip" then
          Note(changes.released, guid, entry.itemID, entry.count + entry.added, "gone")
        else
          departed[#departed + 1] = { guid = guid, entry = entry }
        end
      elseif not ctx.fenced and known.place == "bag" then
        state.gone[guid] = { itemID = known.itemID, count = known.count, at = ctx.now }
      end
    elseif now.count < known.count then
      NoteContainerDrop(state, guid, known)
      local entry = state.pile[guid]
      local left = known.count - now.count
      if IsPure(entry) then
        PoolAdd(pool, entry.itemID, math.min(left, entry.count), entry.runId, entry.pref == "keep", true)
        entry.count = math.min(entry.count, now.count)
      elseif entry then
        entry.added = math.min(entry.added, now.count)
        entry.count = math.min(entry.count, now.count)
      end
    end
  end
end

-- Units that left the character: retire claimed units first (never keep a
-- selling allowance alive through an unexplained drop)
local function RetireLosses(pool, deltas)
  for itemID, delta in pairs(deltas) do
    if delta < 0 and pool[itemID] then
      local p = pool[itemID]
      p.units = math.max(0, p.units + delta)
    end
  end
end

-------------------------------------------------------------------------------
-- Step 3: new stacks and growing stacks
-------------------------------------------------------------------------------
local function NewEntry(state, guid, item, ctx, runId)
  local entry = {
    itemID = item.itemID, link = item.link, count = 0, added = 0,
    runId = runId or ctx.runId, at = ctx.now,
  }
  state.pile[guid] = entry
  return entry
end

-- A GUID not seen before (loot, a split, a move from the bank, a relog)
-- oldStacks[itemID]: a stack of this item that isn't pure run loot is
-- carried, so a new stack of it could be split from the player's own
local function OnNewStack(state, guid, item, pool, allow, changes, ctx, oldStacks)
  if item.place == "equip" then return end
  local units = item.count
  local fromPool, poolRun, poolKeep = PoolTake(pool, item.itemID, units, ctx)
  local rest = units - fromPool
  if ctx.resync then
    -- Only quantity links this stack to an old claim: keep it, never sell
    if fromPool > 0 then
      local entry = NewEntry(state, guid, item, ctx, poolRun)
      entry.pref = poolKeep and "keep" or nil
      entry.added = fromPool
      entry.hold = Ledger.HOLD_INTERRUPTED
      Note(changes.held, guid, item.itemID, fromPool, Ledger.HOLD_INTERRUPTED)
    end
    return
  end
  if ctx.containerOpen and state.container then
    local fromLoot = AllowanceTake(allow, item.itemID, rest)
    if fromPool == 0 and fromLoot == units then
      state.container.pending[guid] = units
      Note(changes.pending, guid, item.itemID, units, "container")
      return
    end
    rest = rest - fromLoot
    fromPool = fromPool + fromLoot   -- counted as run units, but the stack is not pure
    if fromPool > 0 then
      local entry = NewEntry(state, guid, item, ctx, poolRun)
      entry.pref = poolKeep and "keep" or nil
      entry.added = fromPool
      entry.hold = Ledger.HOLD_MIXED
      Note(changes.held, guid, item.itemID, fromPool, Ledger.HOLD_MIXED)
    end
    return
  end
  local fromLoot = AllowanceTake(allow, item.itemID, rest)
  rest = rest - fromLoot
  local runUnits = fromPool + fromLoot
  if runUnits == 0 then return end
  local entry = NewEntry(state, guid, item, ctx, fromLoot > 0 and ctx.runId or poolRun)
  entry.pref = poolKeep and "keep" or nil
  -- New loot counted by the total alone can't be told from a split of the
  -- player's own stack of the same item: shown, never sold
  if fromLoot > 0 and oldStacks[item.itemID] then rest = rest + 1 end
  if rest == 0 then
    entry.count = units
    Note(changes.claimed, guid, item.itemID, units, fromLoot > 0 and "loot" or "moved")
  else
    entry.added = runUnits
    entry.hold = Ledger.HOLD_MIXED
    Note(changes.held, guid, item.itemID, runUnits, Ledger.HOLD_MIXED)
  end
end

-- A known stack that grew
local function OnGrowth(state, guid, item, grew, pool, allow, changes, ctx)
  local entry = state.pile[guid]
  if IsPure(entry) then
    local fromPool, _, poolKeep = PoolTake(pool, item.itemID, grew, ctx)
    if poolKeep then entry.pref = "keep" end
    local fromLoot = 0
    if not ctx.containerOpen then
      fromLoot = AllowanceTake(allow, item.itemID, grew - fromPool)
    end
    local covered = fromPool + fromLoot
    if covered == grew then
      entry.count = entry.count + grew
      Note(changes.claimed, guid, item.itemID, grew, fromLoot > 0 and "loot" or "merged")
    else
      entry.added = entry.count + covered
      entry.count = 0
      Hold(entry, changes, guid, ctx.resync and Ledger.HOLD_INTERRUPTED or Ledger.HOLD_MIXED)
    end
    return
  end
  -- A stack that was already there (or already mixed): run units that land
  -- in it are shown, never sold
  local fromPool = PoolTake(pool, item.itemID, grew, ctx)
  local fromLoot = AllowanceTake(allow, item.itemID, grew - fromPool)
  local runUnits = fromPool + fromLoot
  if runUnits == 0 then return end
  if not entry then entry = NewEntry(state, guid, item, ctx) end
  entry.added = math.min(item.count, entry.added + entry.count + runUnits)
  entry.count = 0
  if entry.hold ~= Ledger.HOLD_MIXED then
    entry.hold = Ledger.HOLD_MIXED
    Note(changes.held, guid, item.itemID, runUnits, Ledger.HOLD_MIXED)
  end
end

-- Item IDs with a carried bag stack that is not pure run loot
local function OldStacks(state, read)
  local old = {}
  for guid, item in pairs(read.items) do
    if item.place == "bag" and state.known[guid] and not IsPure(state.pile[guid]) then
      old[item.itemID] = true
    end
  end
  return old
end

local function CollectArrivals(state, read, pool, allow, changes, ctx)
  local oldStacks = OldStacks(state, read)
  -- Growth first, so a merge of two claimed stacks is matched before a new
  -- stack elsewhere could take the pool
  for guid, item in pairs(read.items) do
    local known = state.known[guid]
    if known and item.count > known.count then
      OnGrowth(state, guid, item, item.count - known.count, pool, allow, changes, ctx)
    end
  end
  for guid, item in pairs(read.items) do
    if not state.known[guid] then
      OnNewStack(state, guid, item, pool, allow, changes, ctx, oldStacks)
    end
  end
end

-------------------------------------------------------------------------------
-- Away: loot that left with nothing open to explain it, kept to come back
-------------------------------------------------------------------------------
-- After the arrivals: a departed pure entry whose units another stack took
-- from the pool (a split or merge) is released, the stack that took them
-- carrying the claim; anything else goes away whole. A drop in the owned
-- total proves nothing here: a zone can hide items from the totals too
local function MarkAway(state, departed, pool, changes, ctx)
  -- Takes beyond what shrinking stacks gave are what departed stacks gave
  for _, p in pairs(pool) do
    p.spare = math.max(0, (p.taken or 0) - (p.shrink or 0))
  end
  for _, d in ipairs(departed) do
    local entry = d.entry
    local p = IsPure(entry) and pool[entry.itemID]
    if p and p.spare >= entry.count then
      p.spare = p.spare - entry.count
      Note(changes.released, d.guid, entry.itemID, entry.count + entry.added, "moved")
    else
      entry.awayAt = ctx.now
      state.away[d.guid] = entry
      Note(changes.away, d.guid, entry.itemID, entry.count + entry.added, "left the bags")
    end
  end
end

-- Before the allowance: units of a GUID coming back raised the owned total
-- but are not loot
local function Unallow(deltas, itemID, units)
  if deltas[itemID] then deltas[itemID] = deltas[itemID] - units end
end

-- A player's own item that left with nothing open, back under the same
-- GUID: known again, never new loot
local function ReturnGone(state, read, deltas)
  for guid, g in pairs(state.gone) do
    local item = read.items[guid]
    if item and not state.known[guid] and not state.pile[guid] and not state.away[guid] then
      state.gone[guid] = nil
      state.known[guid] = { itemID = item.itemID, count = item.count, place = item.place, openable = item.openable or nil }
      Unallow(deltas, item.itemID, item.count)
    elseif item then
      state.gone[guid] = nil
    end
  end
end

local function PruneGone(state, ctx)
  if type(ctx.now) ~= "number" then return end
  local limit = ctx.now - Ledger.AWAY_DAYS * 86400
  local list = {}
  for guid, g in pairs(state.gone) do
    if type(g.at) ~= "number" or g.at < limit then
      state.gone[guid] = nil
    else
      list[#list + 1] = { guid = guid, at = g.at }
    end
  end
  if #list > Ledger.GONE_MAX then
    table.sort(list, function(a, b) return a.at < b.at end)
    for i = 1, #list - Ledger.GONE_MAX do state.gone[list[i].guid] = nil end
  end
end

-- Before the departures: an away GUID back in the bags rejoins the pile as
-- it was (the same stack size, else held), and counts as known, not new.
-- One back equipped (or as something else) is the player's: released, so
-- the history closes it and no rescue brings it back (TRACK-01)
local function ReturnAway(state, read, changes, deltas)
  for guid, entry in pairs(state.away) do
    local item = read.items[guid]
    if item and item.place == "bag" and item.itemID == entry.itemID and not state.known[guid] then
      state.away[guid] = nil
      entry.awayAt = nil
      local size = entry.hold == nil and entry.count or entry.added
      if item.count ~= size then
        entry.added = math.min(item.count, entry.count + entry.added)
        entry.count = 0
        entry.hold = entry.hold or Ledger.HOLD_INTERRUPTED
      end
      state.pile[guid] = entry
      state.known[guid] = { itemID = item.itemID, count = item.count, place = item.place }
      Unallow(deltas, item.itemID, item.count)
      Note(changes.claimed, guid, entry.itemID, item.count, "came back")
    elseif item then
      state.away[guid] = nil
      Note(changes.released, guid, entry.itemID, entry.count + entry.added,
        item.place == "equip" and "equipped" or "gone")
    end
  end
end

local function PruneAway(state, ctx)
  if type(ctx.now) ~= "number" then return end
  local limit = ctx.now - Ledger.AWAY_DAYS * 86400
  for guid, entry in pairs(state.away) do
    if type(entry.awayAt) ~= "number" or entry.awayAt < limit then state.away[guid] = nil end
  end
end

-------------------------------------------------------------------------------
-- Step 4: items that were equipped, and resync checks
-------------------------------------------------------------------------------
local function ReleaseEquipped(state, read, changes)
  for guid, item in pairs(read.items) do
    if item.place == "equip" and state.pile[guid] then
      Release(state, changes, guid, "equipped")
    end
  end
end

-- After a login, a claimed stack larger than its claim can't be explained
local function ResyncChecks(state, read, changes)
  for guid, entry in pairs(state.pile) do
    local item = read.items[guid]
    if item and IsPure(entry) and item.count ~= entry.count then
      entry.added = math.min(item.count, entry.count)
      entry.count = 0
      Hold(entry, changes, guid, Ledger.HOLD_INTERRUPTED)
    end
  end
end

local function RefreshLinks(state, read)
  for guid, entry in pairs(state.pile) do
    local item = read.items[guid]
    if item and item.link then entry.link = item.link end
  end
end

local function StoreRead(state, read)
  local known = {}
  for guid, item in pairs(read.items) do
    known[guid] = { itemID = item.itemID, count = item.count, place = item.place, openable = item.openable or nil }
  end
  state.known = known
  -- Only the items this read and the last one hold: the saved state never
  -- grows with every item ever seen. An item that comes back later (from
  -- the bank or the mailbox) arrives behind a fence, so its missing total
  -- never turns it into loot
  local owned = {}
  for itemID, total in pairs(read.owned or {}) do
    if type(total) == "number" then owned[itemID] = total end
  end
  state.owned = owned
end

-------------------------------------------------------------------------------
-- Container sessions
-------------------------------------------------------------------------------
function Ledger.OpenContainerSession(state)
  if not state.container then
    state.container = { pending = {}, claimedDrop = false, otherDrop = false }
  end
end

-- Ends the session: its pending stacks join the pile only when every
-- container used up was run loot and the stack is still as it arrived
function Ledger.CloseContainerSession(state, ctx)
  local session = state.container
  state.container = nil
  local changes = NewChanges()
  if not session then return changes end
  local accept = session.claimedDrop and not session.otherDrop
  for guid, units in pairs(session.pending) do
    local known = state.known[guid]
    if accept and known and known.count == units and not state.pile[guid] then
      state.pile[guid] = {
        itemID = known.itemID, count = units, added = 0,
        runId = ctx and ctx.runId, at = ctx and ctx.now,
      }
      Note(changes.claimed, guid, known.itemID, units, "container")
    end
  end
  return changes
end

-------------------------------------------------------------------------------
-- Reconcile(state, read, ctx) -> changes
--   ctx.runActive, ctx.runId, ctx.fenced, ctx.resync, ctx.containerOpen, ctx.now
-------------------------------------------------------------------------------
function Ledger.Reconcile(state, read, ctx)
  local changes = NewChanges()
  local pool = {}
  local deltas = OwnedDeltas(state, read)
  ReturnGone(state, read, deltas)
  ReturnAway(state, read, changes, deltas)
  local allow = BuildAllowance(deltas, ctx)
  local departed = {}
  ReleaseEquipped(state, read, changes)
  CollectDepartures(state, read, pool, changes, ctx, departed)
  RetireLosses(pool, deltas)
  if ctx.resync then ResyncChecks(state, read, changes) end
  CollectArrivals(state, read, pool, allow, changes, ctx)
  MarkAway(state, departed, pool, changes, ctx)
  PruneAway(state, ctx)
  PruneGone(state, ctx)
  RefreshLinks(state, read)
  StoreRead(state, read)
  return changes
end

-------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------
-- Is this stack wholly run loot (the only kind the seller may touch)?
function Ledger.IsSellable(state, guid, count)
  local entry = state.pile[guid]
  return IsPure(entry) and entry.count == count
end


-- ClaimConversion(state, read, before, conv) -> changes, result
--   before: { known, owned } of the read before this one; conv: { guid,
--   itemID, count, runId, at, hold }. result: nil (the token is still there or
--   nothing new yet: keep waiting), "claimed" or "ambiguous" (several new
--   items: none claimed)
function Ledger.ClaimConversion(state, read, before, conv)
  local changes = NewChanges()
  local still = read.items[conv.guid]
  if still and still.count >= (conv.count or 1) then return changes, nil end
  local found = {}
  for guid, item in pairs(read.items) do
    if item.place == "bag" and not (before.known or {})[guid] and not state.pile[guid] and item.itemID ~= conv.itemID
        and (read.owned and read.owned[item.itemID] or 0) > ((before.owned or {})[item.itemID] or 0) then
      found[#found + 1] = guid
    end
  end
  if #found == 0 then return changes, nil end
  if #found > 1 then return changes, "ambiguous" end
  local guid = found[1]
  local item = read.items[guid]
  -- A token from a mixed or interrupted stack could have been the player's
  -- own: its piece is held, shown, never sold (TRACK-02)
  local entry = { itemID = item.itemID, link = item.link, count = item.count, added = 0,
                  runId = conv.runId, at = conv.at, fromToken = true }
  if conv.hold then
    entry.added, entry.count, entry.hold = item.count, 0, conv.hold
  end
  state.pile[guid] = entry
  state.away[conv.guid] = nil
  if not still then state.pile[conv.guid] = nil end
  Note(changes.claimed, guid, item.itemID, item.count, "token")
  return changes, "claimed"
end

-- Rescue(state, read, records): records = { { guid, itemID, count, runId,
-- link, at, fromToken } } of run loot never sold; one in a carried bag and in neither the
-- pile nor away rejoins the pile (pure when its stack is the size it was
-- looted at, else held). Returns the changes.
function Ledger.Rescue(state, read, records)
  local changes = NewChanges()
  for _, rec in ipairs(records or {}) do
    local guid = rec.guid
    local item = type(guid) == "string" and read.items[guid]
    if item and item.place == "bag" and item.itemID == rec.itemID and not state.pile[guid] and not state.away[guid]
        and type(rec.count) == "number" and rec.count > 0 then
      local entry = { itemID = rec.itemID, link = item.link or rec.link, count = 0, added = 0, runId = rec.runId,
                      at = rec.at, fromToken = rec.fromToken == true or nil }
      if item.count == rec.count then
        entry.count = item.count
      else
        entry.added = math.min(item.count, rec.count)
        entry.hold = Ledger.HOLD_INTERRUPTED
      end
      state.pile[guid] = entry
      Note(changes.claimed, guid, rec.itemID, item.count, "rescued")
    end
  end
  return changes
end

-- Forget(state[, runId]): the whole pile, or one run's entries (0: entries
-- with no run)
function Ledger.Forget(state, runId)
  if runId == nil then
    state.pile = {}
    state.away = {}
    state.container = nil
    return
  end
  for _, list in ipairs({ state.pile, state.away }) do
    for guid, entry in pairs(list) do
      if (entry.runId or 0) == runId then list[guid] = nil end
    end
  end
end
