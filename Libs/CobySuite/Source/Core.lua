-- CobySuite: Shared library for all CobySuite addons
-- All shared utilities, UI factories, and infrastructure live here.
-- Individual addons (CobySniper, CobysLinkepedia, etc.) depend on this.

CobySuite_CobysLootSweeper = CobySuite_CobysLootSweeper or {}

-- Sub-namespace declarations (populated by individual modules)
CobySuite_CobysLootSweeper.Utilities = CobySuite_CobysLootSweeper.Utilities or {}
CobySuite_CobysLootSweeper.UI        = CobySuite_CobysLootSweeper.UI or {}
CobySuite_CobysLootSweeper.Debug     = CobySuite_CobysLootSweeper.Debug or {}
CobySuite_CobysLootSweeper.Config    = CobySuite_CobysLootSweeper.Config or {}
CobySuite_CobysLootSweeper.EventBus  = CobySuite_CobysLootSweeper.EventBus or {}
CobySuite_CobysLootSweeper.Chat      = CobySuite_CobysLootSweeper.Chat or {}
CobySuite_CobysLootSweeper.Slash     = CobySuite_CobysLootSweeper.Slash or {}
CobySuite_CobysLootSweeper.Tests     = CobySuite_CobysLootSweeper.Tests or {}

CobySuite_CobysLootSweeper.SortDir = { ASC = "asc", DESC = "desc" }

-- Where this copy of the library comes from. The monorepo's CobySuite addon
-- leaves it as is; a standalone build embeds the library under its own name
-- and replaces it from its Build.lua with { embedded = true, host = "<addon>",
-- commit = "<short sha>", dirty = <bool> }.
CobySuite_CobysLootSweeper.BuildInfo = CobySuite_CobysLootSweeper.BuildInfo or { embedded = false }

-- The library version for reports: "embedded in <host> at <commit>" in a
-- standalone build, else the CobySuite addon's TOC version. The addon name
-- below is the only string literal in shipped shared code that is exactly
-- the library's name (the standalone build checks this; Source/Tests/ is
-- stripped).
function CobySuite_CobysLootSweeper.LibraryVersionText()
  local info = CobySuite_CobysLootSweeper.BuildInfo
  if info and info.embedded then
    return ("embedded in %s at %s"):format(tostring(info.host or "?"), tostring(info.commit or "?"))
  end
  return C_AddOns.GetAddOnMetadata("CobySuite", "Version") or "?"
end
