-- Scanner backend: AI tile recommendations. Mirrors the on-map anchor
-- markers the game places for Settlers and Workers by calling the same
-- Player:GetRecommendedFoundCityPlots / GetRecommendedWorkerPlots APIs
-- the engine uses in GenericWorldAnchor.lua.
--
-- Gating mirrors InGame.lua's anchor-fire pipeline exactly:
--   * OptionsManager.IsNoTileRecommendations()  player-toggleable hide
--   * UI.CanSelectionListFound() + player has     settler-rec emit gate
--     at least one city
--   * UI.CanSelectionListWork()                   worker-rec emit gate
--   * player:CanFound(x, y) per settler plot      drops plots that
--                                                 became unfoundable
--                                                 (mirrors the same
--                                                 guard in HandleSettlerRecommendation)
--
-- Category declares subcategories = {}; entries target the implicit
-- `all` sub. Settler recs and worker recs cannot coexist in one
-- selection frame (a unit is either a Founder or a Worker, not both),
-- so a sub-split would add navigation with no payoff.

ScannerBackendRecommendations = {
    name = "recommendations",
}

local CITY_SITE_KEY = "TXT_KEY_CIVVACCESS_SCANNER_RECOMMENDATION_CITY_SITE"

-- Both gates also short-circuit when OptionsManager isn't present (the
-- test harness doesn't stub it by default); returning false keeps Scan
-- empty rather than crashing offline.
local function recsAllowed()
    return OptionsManager ~= nil
        and OptionsManager.IsNoTileRecommendations ~= nil
        and not OptionsManager.IsNoTileRecommendations()
end

local function settlerGateOpen(player)
    return UI ~= nil
        and UI.CanSelectionListFound ~= nil
        and UI.CanSelectionListFound()
        and player ~= nil
        and player:GetNumCities() > 0
end

local function workerGateOpen()
    return UI ~= nil and UI.CanSelectionListWork ~= nil and UI.CanSelectionListWork()
end

local function buildItemName(buildType)
    local row = GameInfo.Builds and GameInfo.Builds[buildType]
    if row == nil or row.Description == nil then
        Log.warn("ScannerBackendRecommendations: worker rec has no GameInfo.Builds row for buildType " .. tostring(buildType))
        return nil
    end
    return Text.key(row.Description)
end

local function emitSettlerEntries(player, out)
    local plots = player:GetRecommendedFoundCityPlots()
    if type(plots) ~= "table" then
        return
    end
    local cityLabel = Text.key(CITY_SITE_KEY)
    for _, plot in ipairs(plots) do
        if plot ~= nil then
            local x, y = plot:GetX(), plot:GetY()
            if player:CanFound(x, y) then
                out[#out + 1] = {
                    plotIndex = plot:GetPlotIndex(),
                    backend = ScannerBackendRecommendations,
                    data = { kind = "settler" },
                    category = "recommendations",
                    subcategory = "all",
                    itemName = cityLabel,
                    sortKey = 0,
                }
            end
        end
    end
end

local function emitWorkerEntries(player, out)
    local recs = player:GetRecommendedWorkerPlots()
    if type(recs) ~= "table" then
        return
    end
    for _, rec in ipairs(recs) do
        local plot = rec and rec.plot
        local buildType = rec and rec.buildType
        if plot ~= nil and buildType ~= nil then
            local name = buildItemName(buildType)
            if name ~= nil then
                out[#out + 1] = {
                    plotIndex = plot:GetPlotIndex(),
                    backend = ScannerBackendRecommendations,
                    data = { kind = "worker", buildType = buildType },
                    category = "recommendations",
                    subcategory = "all",
                    itemName = name,
                    sortKey = 0,
                }
            end
        end
    end
end

function ScannerBackendRecommendations.Scan(activePlayer, _activeTeam)
    local out = {}
    if not recsAllowed() then
        return out
    end
    local player = Players and Players[activePlayer]
    if player == nil then
        return out
    end
    if settlerGateOpen(player) then
        emitSettlerEntries(player, out)
    end
    if workerGateOpen() then
        emitWorkerEntries(player, out)
    end
    return out
end

-- ValidateEntry re-runs the gating and checks whether the plot is still
-- in the fresh rec list. Membership rather than just-CanFound for
-- settlers because a city going up within the min-city-distance circle
-- could keep CanFound true at (x, y) while the engine's strategic
-- assessment drops the plot from the rec list; for workers because the
-- recommended build on a plot can change (e.g. Farm -> Pasture when a
-- cattle resource is revealed by tech).
local function findSettlerPlot(player, x, y)
    local plots = player:GetRecommendedFoundCityPlots()
    if type(plots) ~= "table" then
        return false
    end
    for _, plot in ipairs(plots) do
        if plot ~= nil and plot:GetX() == x and plot:GetY() == y then
            return true
        end
    end
    return false
end

local function findWorkerPlot(player, x, y, buildType)
    local recs = player:GetRecommendedWorkerPlots()
    if type(recs) ~= "table" then
        return false
    end
    for _, rec in ipairs(recs) do
        local plot = rec and rec.plot
        if plot ~= nil and plot:GetX() == x and plot:GetY() == y and rec.buildType == buildType then
            return true
        end
    end
    return false
end

function ScannerBackendRecommendations.ValidateEntry(entry, _cursorPlotIndex)
    if not recsAllowed() then
        return false
    end
    local plot = Map.GetPlotByIndex(entry.plotIndex)
    if plot == nil then
        return false
    end
    local player = Players and Players[Game.GetActivePlayer()]
    if player == nil then
        return false
    end
    local x, y = plot:GetX(), plot:GetY()
    if entry.data.kind == "settler" then
        if not settlerGateOpen(player) then
            return false
        end
        if not player:CanFound(x, y) then
            return false
        end
        return findSettlerPlot(player, x, y)
    elseif entry.data.kind == "worker" then
        if not workerGateOpen() then
            return false
        end
        return findWorkerPlot(player, x, y, entry.data.buildType)
    end
    return false
end

function ScannerBackendRecommendations.FormatName(entry)
    return entry.itemName
end

ScannerCore.registerBackend(ScannerBackendRecommendations)
