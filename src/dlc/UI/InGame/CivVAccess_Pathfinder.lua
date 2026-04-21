-- Lua-side A* pathfinder for target-mode move preview. The engine's
-- own pathfinder is off-limits from Lua (Unit:GeneratePath is NYI;
-- Plot:MovementCost access-violates CvGameCore_Expansion2.dll). See
-- CivVAccess_PlotComposers.lua:143-172 for the full incident log.
--
-- Rules ported from CvUnitMovement::GetCostsForMove (Community Patch
-- fork of the Firaxis DLL drop). MP costs are in 60ths, matching the
-- engine's MOVE_DENOMINATOR. Deliberately scope-limited: no stacking,
-- no HP damage modelling, no canal/city-bridge naval transit. See the
-- implementation plan for the full deferred list.

Pathfinder = {}

local MOVE_DENOM = GameDefines and GameDefines.MOVE_DENOMINATOR or 60

local NEIGHBOR_DIRS = {
    DirectionTypes.DIRECTION_NORTHEAST,
    DirectionTypes.DIRECTION_EAST,
    DirectionTypes.DIRECTION_SOUTHEAST,
    DirectionTypes.DIRECTION_SOUTHWEST,
    DirectionTypes.DIRECTION_WEST,
    DirectionTypes.DIRECTION_NORTHWEST,
}

-- Safety cap: if we expand this many nodes we're almost certainly
-- stuck in a pathological case (massive ocean with no land route, or
-- an enormous map). Bail with "unreachable" rather than freeze speech.
local MAX_EXPANSIONS = 4000

-- ===== Binary min-heap, keyed by item.f =====

local function heapPush(h, item)
    h[#h + 1] = item
    local i = #h
    while i > 1 do
        local parent = math.floor(i / 2)
        if h[parent].f > h[i].f then
            h[parent], h[i] = h[i], h[parent]
            i = parent
        else
            break
        end
    end
end

local function heapPop(h)
    local n = #h
    if n == 0 then
        return nil
    end
    local top = h[1]
    if n == 1 then
        h[1] = nil
        return top
    end
    h[1] = h[n]
    h[n] = nil
    n = n - 1
    local i = 1
    while true do
        local l = 2 * i
        local r = 2 * i + 1
        local smallest = i
        if l <= n and h[l].f < h[smallest].f then
            smallest = l
        end
        if r <= n and h[r].f < h[smallest].f then
            smallest = r
        end
        if smallest == i then
            break
        end
        h[smallest], h[i] = h[i], h[smallest]
        i = smallest
    end
    return top
end

-- ===== GameInfo lookup helpers =====

local function typeId(key)
    if GameInfoTypes == nil then
        return nil
    end
    return GameInfoTypes[key]
end

local function teamHasTech(pTeam, techKey)
    if pTeam == nil or pTeam.IsHasTech == nil then
        return false
    end
    local tid = typeId(techKey)
    if tid == nil then
        return false
    end
    return pTeam:IsHasTech(tid)
end

local function unitHasPromotion(unit, promoKey)
    if unit == nil or unit.IsHasPromotion == nil then
        return false
    end
    local pid = typeId(promoKey)
    if pid == nil then
        return false
    end
    return unit:IsHasPromotion(pid)
end

-- Collect trait-boolean flags the pathfinder cares about, by joining
-- GameInfo.Leader_Traits -> GameInfo.Traits for the player's leader.
-- Degrades to all-false when GameInfo tables aren't iterable (tests
-- that don't install them, or stripped game data). Caller can override
-- by stuffing explicit flags onto ctx after build.
local function collectTraitFlags(player)
    local flags = {
        fasterInHills = false,
        crossesMountains = false,
        embarkedAllWater = false,
        embarkedFlatCost = false,
        woodsAsRoad = false,
        fasterAlongRiver = false,
    }
    if player == nil or player.GetLeaderType == nil then
        return flags
    end
    local leaderType = player:GetLeaderType()
    if leaderType == nil or leaderType < 0 then
        return flags
    end
    if GameInfo == nil or GameInfo.Leaders == nil or GameInfo.Leader_Traits == nil or GameInfo.Traits == nil then
        return flags
    end
    local leaderRow = GameInfo.Leaders[leaderType]
    if leaderRow == nil then
        return flags
    end
    local leaderTypeName = leaderRow.Type
    local ok, iter = pcall(GameInfo.Leader_Traits)
    if not ok or iter == nil then
        return flags
    end
    for row in iter do
        if row.LeaderType == leaderTypeName then
            local traitRow = GameInfo.Traits[row.TraitType]
            if traitRow ~= nil then
                if traitRow.FasterInHills then
                    flags.fasterInHills = true
                end
                if traitRow.CrossesMountainsAfterGreatGeneral then
                    flags.crossesMountains = true
                end
                if traitRow.EmbarkedAllWater then
                    flags.embarkedAllWater = true
                end
                if traitRow.EmbarkedToLandFlatCost then
                    flags.embarkedFlatCost = true
                end
                if traitRow.MoveFriendlyWoodsAsRoad then
                    flags.woodsAsRoad = true
                end
                if traitRow.FasterAlongRiver then
                    flags.fasterAlongRiver = true
                end
            end
        end
    end
    return flags
end

-- Is this plot a TERRAIN_OCEAN (deep water) as opposed to TERRAIN_COAST?
-- Naval units without Astronomy (or the Polynesia EmbarkedAllWater trait)
-- are blocked from entering deep ocean.
local function isDeepOcean(plot)
    local tid = plot:GetTerrainType()
    if tid == nil or tid < 0 then
        return false
    end
    if GameInfo == nil or GameInfo.Terrains == nil then
        return false
    end
    local trow = GameInfo.Terrains[tid]
    return trow ~= nil and trow.Type == "TERRAIN_OCEAN"
end

-- ===== ZoC and Great-Wall precompute =====

-- Enemy combat units project ZoC onto all six neighboring plots.
-- Entering a ZoC-tile from a non-ZoC tile ends the turn per the
-- engine's movement rules. One sweep of every visible enemy combat
-- unit marks the set; A* does an O(1) lookup per step.
local function buildZoCPlots(ctx)
    local zoc = {}
    if Players == nil or GameDefines == nil or GameDefines.MAX_CIV_PLAYERS == nil then
        return zoc
    end
    for pid = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
        local p = Players[pid]
        if p ~= nil and p.IsAlive and p:IsAlive() and p:GetTeam() ~= ctx.team then
            if p.Units ~= nil then
                for unit in p:Units() do
                    if unit ~= nil and unit:IsCombatUnit() and not unit:IsInvisible(ctx.team, ctx.isDebug) then
                        local plot = unit:GetPlot()
                        if plot ~= nil then
                            local ux, uy = plot:GetX(), plot:GetY()
                            for _, dir in ipairs(NEIGHBOR_DIRS) do
                                local n = Map.PlotDirection(ux, uy, dir)
                                if n ~= nil then
                                    zoc[n:GetPlotIndex()] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return zoc
end

-- Plots owned by an at-war civ that has built the Great Wall wonder
-- trigger an end-turn on entry. Precompute: for each opposing player
-- that owns the wonder and is at war with us, walk their owned plots
-- via Player:GetNumPlots / GetPlotByIndex. If those aren't available,
-- the set stays empty and we simply miss the surcharge (the path is
-- still legal, just cheaper than the engine would rate it).
local function buildGreatWallPlots(ctx)
    local walls = {}
    if Players == nil or GameDefines == nil or GameDefines.MAX_CIV_PLAYERS == nil then
        return walls
    end
    local gwClass = typeId("BUILDINGCLASS_GREAT_WALL")
    if gwClass == nil then
        return walls
    end
    for pid = 0, GameDefines.MAX_CIV_PLAYERS - 1 do
        local p = Players[pid]
        if p ~= nil and p.IsAlive and p:IsAlive() and p:GetTeam() ~= ctx.team then
            if p.GetBuildingClassCount and p:GetBuildingClassCount(gwClass) > 0 then
                local otherTeam = p:GetTeam()
                if ctx.pTeam ~= nil and ctx.pTeam:IsAtWar(otherTeam) then
                    if Map ~= nil and Map.GetNumPlots and Map.GetPlotByIndex then
                        for i = 0, Map.GetNumPlots() - 1 do
                            local plot = Map.GetPlotByIndex(i)
                            if plot ~= nil and plot:GetOwner() == pid then
                                walls[plot:GetPlotIndex()] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return walls
end

-- ===== Per-search context =====

local function buildCtx(unit)
    local ctx = {}
    ctx.unit = unit
    ctx.team = unit:GetTeam()
    ctx.player = unit:GetOwner()
    ctx.isDebug = Game.IsDebugMode()
    ctx.pTeam = Teams[ctx.team]
    ctx.maxMoves = unit:MaxMoves()
    if ctx.maxMoves == nil or ctx.maxMoves <= 0 then
        ctx.maxMoves = MOVE_DENOM
    end
    ctx.domain = unit:GetDomainType()
    ctx.isHover = ctx.domain == DomainTypes.DOMAIN_HOVER or unitHasPromotion(unit, "PROMOTION_HOVERING_UNIT")
    ctx.hasEngineering = teamHasTech(ctx.pTeam, "TECH_ENGINEERING")
    ctx.hasAstronomy = teamHasTech(ctx.pTeam, "TECH_ASTRONOMY")
    ctx.canEmbark = ctx.pTeam ~= nil and ctx.pTeam.CanEmbark and ctx.pTeam:CanEmbark() or false
    ctx.ignoresTerrain = unitHasPromotion(unit, "PROMOTION_IGNORE_TERRAIN_COST")
    ctx.isRiverCrossingNoPenalty = unitHasPromotion(unit, "PROMOTION_AMPHIBIOUS")
        or (unit.IsRiverCrossingNoPenalty ~= nil and unit:IsRiverCrossingNoPenalty())
    ctx.flatMovementCost = unitHasPromotion(unit, "PROMOTION_FLAT_MOVEMENT_COST")
    ctx.roughEndsTurn = unitHasPromotion(unit, "PROMOTION_ROUGH_TERRAIN_ENDS_TURN")
    local trait = collectTraitFlags(Players and Players[ctx.player] or nil)
    ctx.fasterInHills = trait.fasterInHills
    ctx.canCrossMountains = trait.crossesMountains
    ctx.embarkedAllWater = trait.embarkedAllWater
    ctx.embarkedFlatCost = trait.embarkedFlatCost or ctx.flatMovementCost
    ctx.woodsAsRoad = trait.woodsAsRoad
    ctx.fasterAlongRiver = trait.fasterAlongRiver
    ctx.canCrossOceans = ctx.hasAstronomy or ctx.embarkedAllWater
    ctx.canEmbark = ctx.canEmbark or ctx.embarkedAllWater
    ctx.zocPlots = buildZoCPlots(ctx)
    ctx.greatWallPlots = buildGreatWallPlots(ctx)
    return ctx
end

-- ===== Cost function =====

-- Rough terrain = hills, forest, jungle (the tiles the engine lists as
-- rough for PROMOTION_ROUGH_TERRAIN_ENDS_TURN). Checked by ID against
-- the types the player's game actually defines; unknown IDs fall
-- through as smooth.
local function isRoughTerrain(plot)
    if plot:IsHills() then
        return true
    end
    local fid = plot:GetFeatureType()
    if fid == nil or fid < 0 then
        return false
    end
    if GameInfo == nil or GameInfo.Features == nil then
        return false
    end
    local row = GameInfo.Features[fid]
    if row == nil then
        return false
    end
    return row.Type == "FEATURE_FOREST" or row.Type == "FEATURE_JUNGLE"
end

-- Base tile cost in 60ths. Feature Movement (if > 0) overrides the
-- terrain's Movement. Hills adds a full MP unless the Inca's
-- FasterInHills trait is set.
local function tileBaseCost(plot, ctx)
    if ctx.ignoresTerrain then
        return MOVE_DENOM
    end
    local cost = MOVE_DENOM
    local fid = plot:GetFeatureType()
    local featureConsumed = false
    if fid ~= nil and fid >= 0 and GameInfo ~= nil and GameInfo.Features ~= nil then
        local frow = GameInfo.Features[fid]
        if frow ~= nil and frow.Movement ~= nil and frow.Movement > 0 then
            cost = frow.Movement * MOVE_DENOM
            featureConsumed = true
        end
    end
    if not featureConsumed then
        local tid = plot:GetTerrainType()
        if tid ~= nil and tid >= 0 and GameInfo ~= nil and GameInfo.Terrains ~= nil then
            local trow = GameInfo.Terrains[tid]
            if trow ~= nil and trow.Movement ~= nil and trow.Movement > 0 then
                cost = trow.Movement * MOVE_DENOM
            end
        end
    end
    if plot:IsHills() and not ctx.fasterInHills then
        cost = cost + MOVE_DENOM
    end
    return cost
end

-- Step cost from fromPlot to toPlot. Returns (mpCost, endsTurn) or
-- nil when the step is illegal (fog, impassable, closed borders, ...).
-- Order of checks mirrors CvUnitMovement::GetCostsForMove: legality
-- gates first, then end-turn triggers, then finally base cost with
-- route / river adjustments.
local function stepCost(fromPlot, toPlot, ctx)
    if not ctx.isDebug and not toPlot:IsRevealed(ctx.team, ctx.isDebug) then
        return nil
    end

    if toPlot:IsMountain() then
        if ctx.isHover then
            -- hover units ignore mountains entirely
        elseif ctx.canCrossMountains then
            return ctx.maxMoves, true
        else
            return nil
        end
    end

    local toIsWater = toPlot:IsWater()
    local fromIsWater = fromPlot:IsWater()

    if ctx.domain == DomainTypes.DOMAIN_LAND and not ctx.isHover then
        if toIsWater then
            if not ctx.canEmbark then
                return nil
            end
            if isDeepOcean(toPlot) and not ctx.canCrossOceans then
                return nil
            end
            if fromIsWater then
                return MOVE_DENOM, false
            else
                if ctx.embarkedFlatCost then
                    return MOVE_DENOM, false
                end
                return ctx.maxMoves, true
            end
        elseif fromIsWater then
            if ctx.embarkedFlatCost then
                return tileBaseCost(toPlot, ctx), false
            end
            return ctx.maxMoves, true
        end
    elseif ctx.domain == DomainTypes.DOMAIN_SEA then
        if not toIsWater then
            if toPlot:IsCity() then
                local city = toPlot:GetPlotCity()
                if city == nil then
                    return nil
                end
                local cityTeam = city.GetTeam and city:GetTeam() or -1
                if cityTeam == ctx.team then
                    return MOVE_DENOM, false
                end
                if ctx.pTeam ~= nil and ctx.pTeam:IsAtWar(cityTeam) then
                    return ctx.maxMoves, true
                end
                return nil
            end
            return nil
        end
        if isDeepOcean(toPlot) and not ctx.canCrossOceans then
            return nil
        end
    end

    local owner = toPlot:GetOwner()
    if owner >= 0 and owner ~= ctx.player and Players ~= nil then
        local ownerPlayer = Players[owner]
        if ownerPlayer ~= nil and ownerPlayer.GetTeam then
            local otherTeam = ownerPlayer:GetTeam()
            if otherTeam ~= ctx.team and ctx.pTeam ~= nil then
                local atWar = ctx.pTeam:IsAtWar(otherTeam)
                local openBorders = ctx.pTeam.IsAllowsOpenBordersToTeam
                    and ctx.pTeam:IsAllowsOpenBordersToTeam(otherTeam)
                if not atWar and not openBorders then
                    return nil
                end
            end
        end
    end

    if toPlot:IsCity() then
        local city = toPlot:GetPlotCity()
        if city ~= nil then
            local cityTeam = city.GetTeam and city:GetTeam() or -1
            if cityTeam ~= ctx.team and ctx.pTeam ~= nil and ctx.pTeam:IsAtWar(cityTeam) then
                return ctx.maxMoves, true
            end
        end
    end

    if ctx.greatWallPlots[toPlot:GetPlotIndex()] then
        return ctx.maxMoves, true
    end

    local fromRoute = fromPlot.GetRouteType and fromPlot:GetRouteType() or -1
    local toRoute = toPlot.GetRouteType and toPlot:GetRouteType() or -1
    local fromPillaged = fromPlot.IsRoutePillaged and fromPlot:IsRoutePillaged() or false
    local toPillaged = toPlot.IsRoutePillaged and toPlot:IsRoutePillaged() or false
    local hasRoute = fromRoute >= 0 and toRoute >= 0 and not fromPillaged and not toPillaged

    -- Trait overlays that make a tile move *as if* it had a road. Iroquois
    -- MoveFriendlyWoodsAsRoad covers forest / jungle in owned territory;
    -- Shoshone-style FasterAlongRiver covers non-crossing steps between
    -- two river-adjacent plots. Either flag lets the route discount apply
    -- even without a built route underneath.
    local riverCrossing = false
    if fromPlot.IsRiverCrossingToPlot ~= nil then
        riverCrossing = fromPlot:IsRiverCrossingToPlot(toPlot)
    end
    local traitRoute = false
    if ctx.woodsAsRoad and toPlot:GetOwner() == ctx.player then
        local fid = toPlot:GetFeatureType()
        if fid ~= nil and fid >= 0 and GameInfo and GameInfo.Features then
            local frow = GameInfo.Features[fid]
            if frow ~= nil and (frow.Type == "FEATURE_FOREST" or frow.Type == "FEATURE_JUNGLE") then
                traitRoute = true
            end
        end
    end
    if
        ctx.fasterAlongRiver
        and not riverCrossing
        and fromPlot.IsRiverSide
        and toPlot.IsRiverSide
        and fromPlot:IsRiverSide()
        and toPlot:IsRiverSide()
    then
        traitRoute = true
    end

    if riverCrossing and not ctx.hasEngineering and not ctx.isRiverCrossingNoPenalty and not hasRoute and not traitRoute then
        return ctx.maxMoves, true
    end

    local base = tileBaseCost(toPlot, ctx)

    local cost = base
    if hasRoute or traitRoute then
        local routeCost = math.huge
        local routeRow = GameInfo and GameInfo.Routes and GameInfo.Routes[toRoute] or nil
        if routeRow ~= nil and routeRow.FlatMovementCost ~= nil then
            routeCost = routeRow.FlatMovementCost * (ctx.maxMoves / MOVE_DENOM)
        elseif traitRoute then
            -- No underlying road; fall back to vanilla road's flat cost of
            -- 10 per MP so the trait still delivers a road-equivalent speedup.
            routeCost = 10 * (ctx.maxMoves / MOVE_DENOM)
        end
        if routeCost < cost then
            cost = routeCost
        end
    end

    local toIdx = toPlot:GetPlotIndex()
    local fromIdx = fromPlot:GetPlotIndex()
    if ctx.zocPlots[toIdx] and not ctx.zocPlots[fromIdx] then
        return cost, true
    end

    if ctx.roughEndsTurn and isRoughTerrain(toPlot) then
        return cost, true
    end

    return cost, false
end

-- ===== A* search =====

-- g(n) = turns consumed * maxMoves + (maxMoves - mpRemaining). Each
-- transition advances (turns, mpRemaining):
--   mpRem==0 entering a step -> the unit ran out of MP on the prior
--     tile, so it has to wait. Bump turn, replenish, then apply the
--     step to the new turn.
--   endsTurn  -> turns+=1, mpRemaining = maxMoves (unused MP wasted)
--   within    -> mpRemaining -= mpCost
--   overflow  -> remaining is wasted, turn++, cost debited against
--     the new turn; can roll across multiple turn boundaries for a
--     1-MP settler entering a 3-MP marsh.
local function advance(turns, mpRemaining, mpCost, endsTurn, maxMoves)
    if mpRemaining == 0 then
        turns = turns + 1
        mpRemaining = maxMoves
    end
    if endsTurn then
        return turns + 1, maxMoves
    end
    if mpCost <= mpRemaining then
        return turns, mpRemaining - mpCost
    end
    local newTurns = turns + 1
    local newRemaining = maxMoves - mpCost
    if newRemaining < 0 then
        local extra = math.ceil(-newRemaining / maxMoves)
        newTurns = newTurns + extra
        newRemaining = newRemaining + extra * maxMoves
    end
    return newTurns, newRemaining
end

local function scoreOf(turns, mpRemaining, maxMoves)
    return turns * maxMoves + (maxMoves - mpRemaining)
end

-- Public entry point. Returns (result, nil) on success where result is
-- { mpCost, turns, maxMoves } with mpCost in 60ths; (nil, reason) on
-- failure.
function Pathfinder.findPath(unit, toPlot)
    if unit == nil then
        return nil, "no_target"
    end
    if toPlot == nil then
        return nil, "no_target"
    end
    local fromPlot = unit:GetPlot()
    if fromPlot == nil then
        return nil, "no_target"
    end
    if fromPlot:GetPlotIndex() == toPlot:GetPlotIndex() then
        return nil, "same_plot"
    end

    local ctx = buildCtx(unit)
    local maxMoves = ctx.maxMoves
    local tx, ty = toPlot:GetX(), toPlot:GetY()

    local startMP = unit:MovesLeft()
    if startMP == nil or startMP < 0 then
        startMP = maxMoves
    end

    local heap = {}
    local gScore = {}
    local cameFrom = {}

    local startIdx = fromPlot:GetPlotIndex()
    gScore[startIdx] = 0
    heapPush(heap, {
        plot = fromPlot,
        plotIndex = startIdx,
        g = 0,
        f = 0,
        turns = 0,
        mpRemaining = startMP,
    })

    local expansions = 0
    while #heap > 0 do
        local current = heapPop(heap)
        expansions = expansions + 1
        if expansions > MAX_EXPANSIONS then
            Log.warn("Pathfinder: hit expansion cap before reaching target; treating as unreachable")
            return nil, "unreachable"
        end

        if current.plotIndex == toPlot:GetPlotIndex() then
            return {
                mpCost = current.g,
                turns = current.turns + (current.mpRemaining < maxMoves and 1 or 0),
                maxMoves = maxMoves,
            }, nil
        end

        if current.g > (gScore[current.plotIndex] or math.huge) then
            -- Superseded by a better path found later; skip.
            -- (Binary heap can't decrease-key, so we push duplicates.)
        else
            local cx, cy = current.plot:GetX(), current.plot:GetY()
            for _, dir in ipairs(NEIGHBOR_DIRS) do
                local neighbor = Map.PlotDirection(cx, cy, dir)
                if neighbor ~= nil then
                    local cost, endsTurn = stepCost(current.plot, neighbor, ctx)
                    if cost ~= nil then
                        local newTurns, newMP = advance(current.turns, current.mpRemaining, cost, endsTurn, maxMoves)
                        local newG = scoreOf(newTurns, newMP, maxMoves)
                        local nIdx = neighbor:GetPlotIndex()
                        if newG < (gScore[nIdx] or math.huge) then
                            gScore[nIdx] = newG
                            cameFrom[nIdx] = current.plotIndex
                            -- h = distance * 2 (60ths) matches the minimum
                            -- per-tile cost of a vanilla railroad at 2 MP
                            -- (FlatMovementCost=1, baseMoves=2), which keeps
                            -- the heuristic admissible for every vanilla
                            -- unit. Using MOVE_DENOM (60) here was non-
                            -- admissible on railroad-heavy paths and A*
                            -- could return a suboptimal turn count.
                            local h = HexGeom.cubeDistance(neighbor:GetX(), neighbor:GetY(), tx, ty) * 2
                            heapPush(heap, {
                                plot = neighbor,
                                plotIndex = nIdx,
                                g = newG,
                                f = newG + h,
                                turns = newTurns,
                                mpRemaining = newMP,
                            })
                        end
                    end
                end
            end
        end
    end

    return nil, "unreachable"
end

-- Internal: exposed for unit tests that want to exercise stepCost with
-- a hand-crafted ctx (explicit promotion / trait flags) rather than
-- driving everything through buildCtx's GameInfo indirection.
Pathfinder._internal = {
    buildCtx = buildCtx,
    stepCost = stepCost,
    tileBaseCost = tileBaseCost,
    MOVE_DENOM = MOVE_DENOM,
}
