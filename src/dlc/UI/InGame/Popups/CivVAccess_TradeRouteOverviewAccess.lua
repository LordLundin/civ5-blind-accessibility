-- Trade Route Overview accessibility (Ctrl+T). Wraps the engine popup as a
-- three-tab TabbedShell, every tab a flat BaseMenu list of route Groups.
--
--   Your trade routes      pPlayer:GetTradeRoutes()
--                          Routes the active player currently runs (caravans
--                          and cargo ships you have in flight).
--   Available trade routes pPlayer:GetTradeRoutesAvailable()
--                          Routes the active player could establish from
--                          idle trade units.
--   Trade routes with you  pPlayer:GetTradeRoutesToYou()
--                          Routes other civs run that terminate in your
--                          cities (their bonuses, your destination).
--
-- The three accessors return rows with the same field shape (see
-- TradeRouteOverview.lua DisplayData), so the row builder is shared.
--
-- Each row's drill-in is the engine's own tooltip
-- (BuildTradeRouteToolTipString) split per [NEWLINE] line. The engine sets
-- that same tooltip on every cell of the row -- gold cells, science cells,
-- religion cells, etc. -- so a sighted player sees one rich tooltip from any
-- cell hover. We surface the same tooltip line by line so a screen-reader
-- user steps through the same content without trying to navigate cells.
--
-- Engine integration: ships an override of TradeRouteOverview.lua (verbatim
-- BNW copy + an include for this module). The engine's OnPopupMessage,
-- OnClose, ShowHideHandler, InputHandler, RegisterSortOptions, TabSelect,
-- and per-tab RefreshContent stay intact; TabbedShell.install layers our
-- handler on top via priorInput / priorShowHide chains. onShow rebuilds
-- every tab's items so a fresh open after a turn change reflects updated
-- TurnsLeft / GPT values.

include("CivVAccess_Polyfill")
include("CivVAccess_Log")
include("CivVAccess_TextFilter")
include("CivVAccess_InGameStrings_en_US")
include("CivVAccess_Text")
include("CivVAccess_SpeechEngine")
include("CivVAccess_SpeechPipeline")
include("CivVAccess_HandlerStack")
include("CivVAccess_InputRouter")
include("CivVAccess_TickPump")
include("CivVAccess_Nav")
include("CivVAccess_BaseMenuItems")
include("CivVAccess_TypeAheadSearch")
include("CivVAccess_BaseMenuHelp")
include("CivVAccess_BaseMenuTabs")
include("CivVAccess_BaseMenuCore")
include("CivVAccess_BaseMenuInstall")
include("CivVAccess_TabbedShell")
include("CivVAccess_Help")

local priorInput = InputHandler
local priorShowHide = ShowHideHandler

-- Tab handles, set during install; module-level so the show hook can
-- rebuild items per tab on every open.
local m_yoursTab
local m_availableTab
local m_withYouTab

-- Civ name resolver. Mirrors the engine's GetCivName() inside SetData,
-- including the city-state branch that swaps to the minor civ short
-- description so "Sidon" reads instead of "City-State". Lifted out of
-- the engine helper to keep us independent of whether the engine's tab
-- RefreshContent has run (we drive our own data fetch).
local function civName(playerID)
    local civType = PreGame.GetCivilization(playerID)
    local civ = GameInfo.Civilizations[civType]
    if civ == nil then
        return Text.key("TXT_KEY_MISC_UNKNOWN")
    end
    local minorCiv = GameInfo.Civilizations["CIVILIZATION_MINOR"]
    if minorCiv ~= nil and civ.ID == minorCiv.ID then
        local minor = Players[playerID]
        local minorType = minor:GetMinorCivType()
        local minorInfo = GameInfo.MinorCivilizations[minorType]
        if minorInfo ~= nil then
            return Text.key(minorInfo.ShortDescription)
        end
    end
    return Text.key(civ.Description)
end

local function domainLabel(domain)
    if domain == DomainTypes.DOMAIN_SEA then
        return Text.key("TXT_KEY_CIVVACCESS_TRO_DOMAIN_SEA")
    end
    return Text.key("TXT_KEY_CIVVACCESS_TRO_DOMAIN_LAND")
end

-- Split engine tooltip text on [NEWLINE] tokens, dropping empty segments.
-- Used to turn the per-cell tooltip into one drill-in line per source
-- [NEWLINE]-separated entry. The engine emits double [NEWLINE] for
-- paragraph breaks; the empty-segment skip collapses those.
local function splitNewlines(s)
    local out = {}
    if s == nil or s == "" then
        return out
    end
    local cursor = 1
    while true do
        local startIdx, endIdx = s:find("%[NEWLINE%]", cursor, false)
        if startIdx == nil then
            local tail = s:sub(cursor)
            local trimmed = tail:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                out[#out + 1] = trimmed
            end
            return out
        end
        local segment = s:sub(cursor, startIdx - 1)
        local trimmed = segment:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            out[#out + 1] = trimmed
        end
        cursor = endIdx + 1
    end
end

-- Build a single drill-in Text item from a tooltip line. The line still
-- carries engine markup ([COLOR_*], [ICON_*], etc.); the speech path
-- runs every announcement through TextFilter, which strips / substitutes
-- those tokens.
local function tooltipLineItem(line)
    return BaseMenuItems.Text({
        labelText = line,
    })
end

local function rowLabel(route)
    local fromCiv = civName(route.FromID)
    local toCiv = civName(route.ToID)
    local turns = route.TurnsLeft or 0
    return Text.format(
        "TXT_KEY_CIVVACCESS_TRO_ROUTE_LABEL",
        domainLabel(route.Domain),
        route.FromCityName,
        fromCiv,
        route.ToCityName,
        toCiv,
        turns
    )
end

-- Capture the route as a snapshot for the label closure, but rebuild the
-- drill-in items live on every drill (cached=false) so the tooltip
-- reflects current turn yields if the user pages between tabs across a
-- turn change.
local function buildRouteGroup(route)
    return BaseMenuItems.Group({
        labelFn = function()
            return rowLabel(route)
        end,
        cached = false,
        itemsFn = function()
            local pPlayer = Players[route.FromID]
            if pPlayer == nil then
                return {
                    BaseMenuItems.Text({
                        labelText = Text.key("TXT_KEY_CIVVACCESS_TRO_NO_ROUTES"),
                    }),
                }
            end
            local tt
            local ok, err = pcall(function()
                tt = BuildTradeRouteToolTipString(pPlayer, route.FromCity, route.ToCity, route.Domain)
            end)
            if not ok then
                Log.error("TradeRouteOverview: BuildTradeRouteToolTipString failed: " .. tostring(err))
                tt = nil
            end
            local items = {}
            for _, line in ipairs(splitNewlines(tt)) do
                items[#items + 1] = tooltipLineItem(line)
            end
            if #items == 0 then
                items[1] = BaseMenuItems.Text({
                    labelText = Text.key("TXT_KEY_CIVVACCESS_TRO_NO_ROUTES"),
                })
            end
            return items
        end,
    })
end

-- Default sort: FromCityName ascending. Matches the engine's default
-- (g_SortOptions row "FromCityHeader" carries CurrentDirection="asc"
-- on initial load), so users hear routes in the same order a sighted
-- player sees on open.
local function sortRoutes(routes)
    table.sort(routes, function(a, b)
        local ka = a.FromCityName or ""
        local kb = b.FromCityName or ""
        return Locale.Compare(ka, kb) == -1
    end)
end

local function buildItemsFromRoutes(routes)
    sortRoutes(routes)
    local items = {}
    for _, route in ipairs(routes) do
        items[#items + 1] = buildRouteGroup(route)
    end
    if #items == 0 then
        items[1] = BaseMenuItems.Text({
            labelText = Text.key("TXT_KEY_CIVVACCESS_TRO_NO_ROUTES"),
        })
    end
    return items
end

local function buildYoursItems()
    local pPlayer = Players[Game.GetActivePlayer()]
    if pPlayer == nil then
        return {}
    end
    return buildItemsFromRoutes(pPlayer:GetTradeRoutes() or {})
end

local function buildAvailableItems()
    local pPlayer = Players[Game.GetActivePlayer()]
    if pPlayer == nil then
        return {}
    end
    return buildItemsFromRoutes(pPlayer:GetTradeRoutesAvailable() or {})
end

local function buildWithYouItems()
    local pPlayer = Players[Game.GetActivePlayer()]
    if pPlayer == nil then
        return {}
    end
    return buildItemsFromRoutes(pPlayer:GetTradeRoutesToYou() or {})
end

-- ===== Install =========================================================

if type(ContextPtr) == "table" and type(ContextPtr.SetShowHideHandler) == "function" then
    local function makeTab(tabName)
        return TabbedShell.menuTab({
            tabName = tabName,
            menuSpec = {
                displayName = Text.key("TXT_KEY_TRADE_ROUTE_OVERVIEW"),
                items = {},
            },
        })
    end
    m_yoursTab = makeTab("TXT_KEY_CIVVACCESS_TRO_TAB_YOURS")
    m_availableTab = makeTab("TXT_KEY_CIVVACCESS_TRO_TAB_AVAILABLE")
    m_withYouTab = makeTab("TXT_KEY_CIVVACCESS_TRO_TAB_WITH_YOU")
    TabbedShell.install(ContextPtr, {
        name = "TradeRouteOverview",
        displayName = Text.key("TXT_KEY_TRADE_ROUTE_OVERVIEW"),
        tabs = { m_yoursTab, m_availableTab, m_withYouTab },
        initialTabIndex = 1,
        priorInput = priorInput,
        priorShowHide = priorShowHide,
        onShow = function(_handler)
            m_yoursTab.menu().setItems(buildYoursItems())
            m_availableTab.menu().setItems(buildAvailableItems())
            m_withYouTab.menu().setItems(buildWithYouItems())
        end,
    })
end
