-- Shared helpers for AI tile recommendations. Owns the gating, list
-- accessors, membership check, and the reason-text ladder that
-- GenericWorldAnchor.lua uses to build its map tooltip. Two consumers:
--   * ScannerBackendRecommendations -- uses gating + list iteration
--     to emit scanner entries.
--   * PlotSections.recommendation   -- uses membership + reason text
--     to append a "recommendation: ..." token to the cursor glance
--     when the user lands on a recommended plot.
--
-- Reason text reimplements the if/elseif ladder in
-- HandleSettlerRecommendation / HandleWorkerRecommendation verbatim,
-- using the same TXT_KEYs. Anything else drifts from what a sighted
-- player sees on the map marker tooltip.

Recommendations = {}

-- ===== Gating =====

function Recommendations.allowed()
    return OptionsManager ~= nil
        and OptionsManager.IsNoTileRecommendations ~= nil
        and not OptionsManager.IsNoTileRecommendations()
end

function Recommendations.settlerActive(player)
    return UI ~= nil
        and UI.CanSelectionListFound ~= nil
        and UI.CanSelectionListFound()
        and player:GetNumCities() > 0
end

function Recommendations.workerActive()
    return UI ~= nil and UI.CanSelectionListWork ~= nil and UI.CanSelectionListWork()
end

-- ===== List accessors =====

function Recommendations.settlerPlots(player)
    local list = player:GetRecommendedFoundCityPlots()
    if type(list) ~= "table" then
        return {}
    end
    return list
end

function Recommendations.workerPlots(player)
    local list = player:GetRecommendedWorkerPlots()
    if type(list) ~= "table" then
        return {}
    end
    return list
end

-- ===== Membership =====

function Recommendations.settlerContains(player, x, y)
    for _, plot in ipairs(Recommendations.settlerPlots(player)) do
        if plot ~= nil and plot:GetX() == x and plot:GetY() == y then
            return true
        end
    end
    return false
end

function Recommendations.workerContains(player, x, y, buildType)
    for _, rec in ipairs(Recommendations.workerPlots(player)) do
        local plot = rec and rec.plot
        if plot ~= nil and plot:GetX() == x and plot:GetY() == y and rec.buildType == buildType then
            return true
        end
    end
    return false
end

-- First worker rec at (x, y), regardless of buildType. Used by the
-- plot section, which doesn't know the buildType up front and just
-- wants "is this plot worker-recommended and, if so, for what."
function Recommendations.workerRecAt(player, x, y)
    for _, rec in ipairs(Recommendations.workerPlots(player)) do
        local plot = rec and rec.plot
        if plot ~= nil and plot:GetX() == x and plot:GetY() == y then
            return rec
        end
    end
    return nil
end

-- ===== Reason builders =====

-- Mirrors HandleSettlerRecommendation's 2-range sum exactly: food /
-- production / gold yields accumulated over every plot within Chebyshev
-- distance 2, luxury and strategic counts only on unowned neighbours
-- (luxuries further filtered to those the player doesn't already own).
-- Priority order is also verbatim: luxuries > strategics > gold > prod
-- > food. Thresholds (0.75 / 0.75 / 1.2 per-plot average) are the
-- engine's numbers; changing them would silently drift our speech from
-- what sighted players see.
local SETTLER_RANGE = 2

function Recommendations.settlerReason(plot, player)
    local activeTeam = Game.GetActiveTeam()
    local iTotalFood, iTotalProduction, iTotalGold = 0, 0, 0
    local iLuxury, iStrategic = 0, 0
    local iNumPlots = 0
    local px, py = plot:GetX(), plot:GetY()
    for dx = -SETTLER_RANGE, SETTLER_RANGE do
        for dy = -SETTLER_RANGE, SETTLER_RANGE do
            local target = Map.GetPlotXY(px, py, dx, dy)
            if target ~= nil then
                local tx, ty = target:GetX(), target:GetY()
                if Map.PlotDistance(px, py, tx, ty) <= SETTLER_RANGE then
                    iNumPlots = iNumPlots + 1
                    iTotalFood = iTotalFood + target:GetYield(YieldTypes.YIELD_FOOD)
                    iTotalProduction = iTotalProduction + target:GetYield(YieldTypes.YIELD_PRODUCTION)
                    iTotalGold = iTotalGold + target:GetYield(YieldTypes.YIELD_GOLD)
                    if not target:IsOwned() then
                        local resId = target:GetResourceType(activeTeam)
                        if resId ~= nil and resId >= 0 then
                            local usage = Game.GetResourceUsageType(resId)
                            if usage == ResourceUsageTypes.RESOURCEUSAGE_LUXURY then
                                if player:GetNumResourceAvailable(resId) == 0 then
                                    iLuxury = iLuxury + 1
                                end
                            elseif usage == ResourceUsageTypes.RESOURCEUSAGE_STRATEGIC then
                                iStrategic = iStrategic + 1
                            end
                        end
                    end
                end
            end
        end
    end
    if iLuxury > 0 then
        return Text.key("TXT_KEY_RECOMMEND_SETTLER_LUXURIES")
    end
    if iStrategic > 0 then
        return Text.key("TXT_KEY_RECOMMEND_SETTLER_STRATEGIC")
    end
    if iNumPlots > 0 then
        if iTotalGold / iNumPlots > 0.75 then
            return Text.key("TXT_KEY_RECOMMEND_SETTLER_GOLD")
        end
        if iTotalProduction / iNumPlots > 0.75 then
            return Text.key("TXT_KEY_RECOMMEND_SETTLER_PRODUCTION")
        end
        if iTotalFood / iNumPlots > 1.2 then
            return Text.key("TXT_KEY_RECOMMEND_SETTLER_FOOD")
        end
    end
    return nil
end

-- Mirrors HandleWorkerRecommendation's ladder: plot-resource hookup
-- (luxury or strategic) takes priority; then the build's own
-- Recommendation text key (few builds define one); otherwise the first
-- positive yield delta produced by the build (food > prod > gold).
function Recommendations.workerReason(plot, buildType)
    local activeTeam = Game.GetActiveTeam()
    local resId = plot:GetResourceType(activeTeam)
    if resId ~= nil and resId >= 0 then
        local row = GameInfo.Resources[resId]
        if row ~= nil and row.ResourceUsage ~= ResourceUsageTypes.RESOURCEUSAGE_BONUS then
            if row.ResourceUsage == ResourceUsageTypes.RESOURCEUSAGE_LUXURY then
                return Text.key("TXT_KEY_RECOMMEND_WORKER_LUXURY")
            end
            return Text.key("TXT_KEY_RECOMMEND_WORKER_STRATEGIC")
        end
    end
    local buildRow = GameInfo.Builds[buildType]
    if buildRow == nil then
        return nil
    end
    if buildRow.Recommendation ~= nil then
        return Text.key(buildRow.Recommendation)
    end
    local activePlayer = Game.GetActivePlayer()
    for iYield = 0, YieldTypes.NUM_YIELD_TYPES - 1 do
        local withBuild = plot:GetYieldWithBuild(buildType, iYield, false, activePlayer)
        local delta = withBuild - plot:CalculateYield(iYield)
        if delta > 0 then
            if iYield == YieldTypes.YIELD_FOOD then
                return Text.key("TXT_KEY_BUILD_FOOD_REC")
            elseif iYield == YieldTypes.YIELD_PRODUCTION then
                return Text.key("TXT_KEY_BUILD_PROD_REC")
            elseif iYield == YieldTypes.YIELD_GOLD then
                return Text.key("TXT_KEY_BUILD_GOLD_REC")
            end
        end
    end
    return nil
end
