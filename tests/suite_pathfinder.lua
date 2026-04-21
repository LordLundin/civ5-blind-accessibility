-- Pathfinder: A* over the hex grid with a scope-limited port of
-- CvUnitMovement::GetCostsForMove. Each test exercises a distinct rule
-- branch — terrain base cost, hills surcharge, route discount, river
-- crossing end-turn, embarkation, mountain impassable, territory access,
-- ZoC, Great Wall, and trait overrides for Inca / Carthage / Polynesia.

local T = require("support")
local M = {}

-- Feature / terrain / route / tech / trait / promotion / building-class
-- IDs used across the suite. Keep them stable so every test agrees on
-- which row GameInfo.X[id] resolves to.
local FEAT_FOREST = 1
local TERRAIN_GRASS = 1
local TERRAIN_COAST = 2
local TERRAIN_OCEAN = 3
local ROUTE_ROAD = 0
local TECH_ENGINEERING = 10
local TECH_ASTRONOMY = 11
local PROMOTION_IGNORE_TERRAIN_COST = 20
local PROMOTION_AMPHIBIOUS = 21
local PROMOTION_HOVERING_UNIT = 22
local PROMOTION_ROUGH_TERRAIN_ENDS_TURN = 23
local PROMOTION_FLAT_MOVEMENT_COST = 24
local BUILDINGCLASS_GREAT_WALL = 30

local function setup()
    dofile("src/dlc/UI/InGame/CivVAccess_Pathfinder.lua")

    Game.GetActivePlayer = function()
        return 0
    end
    Game.GetActiveTeam = function()
        return 0
    end
    Game.IsDebugMode = function()
        return false
    end

    GameDefines = GameDefines or {}
    GameDefines.MOVE_DENOMINATOR = 60
    GameDefines.MAX_CIV_PLAYERS = 4

    GameInfoTypes = {
        TECH_ENGINEERING = TECH_ENGINEERING,
        TECH_ASTRONOMY = TECH_ASTRONOMY,
        PROMOTION_IGNORE_TERRAIN_COST = PROMOTION_IGNORE_TERRAIN_COST,
        PROMOTION_AMPHIBIOUS = PROMOTION_AMPHIBIOUS,
        PROMOTION_HOVERING_UNIT = PROMOTION_HOVERING_UNIT,
        PROMOTION_ROUGH_TERRAIN_ENDS_TURN = PROMOTION_ROUGH_TERRAIN_ENDS_TURN,
        PROMOTION_FLAT_MOVEMENT_COST = PROMOTION_FLAT_MOVEMENT_COST,
        BUILDINGCLASS_GREAT_WALL = BUILDINGCLASS_GREAT_WALL,
    }

    -- Minimal data tables. Movement columns drive tileBaseCost; Type
    -- strings drive ocean / forest / jungle branch detection.
    GameInfo = {
        Terrains = {
            [TERRAIN_GRASS] = { Type = "TERRAIN_GRASS", Movement = 1 },
            [TERRAIN_COAST] = { Type = "TERRAIN_COAST", Movement = 1 },
            [TERRAIN_OCEAN] = { Type = "TERRAIN_OCEAN", Movement = 1 },
        },
        Features = {
            [FEAT_FOREST] = { Type = "FEATURE_FOREST", Movement = 2 },
        },
        Routes = {
            [ROUTE_ROAD] = { Type = "ROUTE_ROAD", FlatMovementCost = 10 },
        },
        Leaders = {},
        Leader_Traits = function()
            return function()
                return nil
            end
        end,
        Traits = {},
    }

    Players = {}
    Teams = {}
    Map.PlotDirection = function()
        return nil
    end
    Map.GetPlot = function()
        return nil
    end
    Map.GetNumPlots = function()
        return 0
    end
    Map.GetPlotByIndex = function()
        return nil
    end
end

-- Install a hex-offset grid. `configure(col, row, plot)` may return a
-- replacement plot to override the defaults. plotIndex is col+row*(2W+1)
-- so every plot has a unique index for cameFrom / zocPlots lookup.
local function installGrid(halfWidth, configure)
    local plots = {}
    local idx = 0
    for col = -halfWidth, halfWidth do
        plots[col] = {}
        for row = -halfWidth, halfWidth do
            local p = T.fakePlot({
                x = col,
                y = row,
                plotIndex = idx,
                terrain = TERRAIN_GRASS,
                plotType = PlotTypes.PLOT_LAND,
            })
            idx = idx + 1
            if configure ~= nil then
                local override = configure(col, row, p)
                if override ~= nil then
                    p = override
                end
            end
            plots[col][row] = p
        end
    end
    local function lookup(col, row)
        local column = plots[col]
        if column == nil then
            return nil
        end
        return column[row]
    end
    Map.GetPlot = lookup
    -- Offset (even-row) neighbor deltas. Pathfinder iterates the six
    -- hex directions via Map.PlotDirection; this table converts each
    -- direction to a (dcol, drow) offset. Parity (even / odd row) shifts
    -- E-facing neighbors; the grid configuration in these tests keeps
    -- the actor near the origin so parity differences don't matter for
    -- the properties under test.
    local function neighborOffset(col, row, dir)
        local even = (row % 2 == 0)
        if dir == DirectionTypes.DIRECTION_EAST then
            return col + 1, row
        elseif dir == DirectionTypes.DIRECTION_WEST then
            return col - 1, row
        elseif dir == DirectionTypes.DIRECTION_NORTHEAST then
            return (even and col or col + 1), row - 1
        elseif dir == DirectionTypes.DIRECTION_NORTHWEST then
            return (even and col - 1 or col), row - 1
        elseif dir == DirectionTypes.DIRECTION_SOUTHEAST then
            return (even and col or col + 1), row + 1
        elseif dir == DirectionTypes.DIRECTION_SOUTHWEST then
            return (even and col - 1 or col), row + 1
        end
        return col, row
    end
    Map.PlotDirection = function(x, y, dir)
        local nx, ny = neighborOffset(x, y, dir)
        return lookup(nx, ny)
    end
    Map.GetNumPlots = function()
        return idx
    end
    Map.GetPlotByIndex = function(i)
        for col = -halfWidth, halfWidth do
            for row = -halfWidth, halfWidth do
                local p = plots[col][row]
                if p:GetPlotIndex() == i then
                    return p
                end
            end
        end
        return nil
    end
    return plots
end

-- Produce a warrior-shaped unit at `plot` with the given promotions,
-- plus a team at the same id. Team flags (techs, open borders, etc.)
-- override the default "nothing researched / no agreements" baseline.
local function mkUnit(plot, opts)
    opts = opts or {}
    local unit = T.fakeUnit({
        owner = 0,
        team = 0,
        domain = opts.domain or DomainTypes.DOMAIN_LAND,
        maxMoves = opts.maxMoves or 120,
        movesLeft = opts.movesLeft or (opts.maxMoves or 120),
        promotions = opts.promotions or {},
    })
    unit._plot = plot
    Teams[0] = T.fakeTeam({
        techs = opts.techs or {},
        openBorders = opts.openBorders or {},
        canEmbark = opts.canEmbark or false,
    })
    Players[0] = {
        _team = 0,
        GetTeam = function(self)
            return 0
        end,
        GetLeaderType = function()
            return -1
        end,
        IsAlive = function()
            return true
        end,
        GetBuildingClassCount = function(_, _)
            return 0
        end,
        Units = function()
            return function()
                return nil
            end
        end,
    }
    return unit
end

-- ===== Tests =====

-- 1. Straight-line open grass: three hexes (cost 60 each), unit has
-- 2 MP / turn. Step 1 mpRem=60. Step 2 mpRem=0. Step 3 overflows:
-- newRemaining = 120-60 = 60, turns=1. Final mpRemaining < maxMoves
-- so final_turns = 1 + 1 = 2.
function M.test_straight_line_open_grass_three_hexes()
    setup()
    local plots = installGrid(4)
    local unit = mkUnit(plots[0][0], {})
    local result, reason = Pathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil, "expected path, got nil: " .. tostring(reason))
    T.eq(result.turns, 2, "3 grass hexes with 2 MP per turn should take 2 turns")
    T.eq(result.mpCost, 180, "3 * 60 MP = 180 in 60ths")
end

-- 2. Hills add 1 MP. Two-hex path grass -> hill takes 2 turns (hill
-- exceeds the 60 MP left after step 1), while a two-hex grass-grass
-- path finishes this turn. The difference isolates the hill surcharge.
function M.test_hills_surcharge_forces_extra_turn()
    setup()
    local plotsGrass = installGrid(4)
    local unitGrass = mkUnit(plotsGrass[0][0], {})
    local resultGrass = Pathfinder.findPath(unitGrass, plotsGrass[2][0])
    T.eq(resultGrass.turns, 1, "grass-grass should fit in one turn")

    setup()
    local plotsHills = installGrid(4, function(col, row, p)
        if col == 2 and row == 0 then
            p._isHills = true
        end
        return p
    end)
    local unitHills = mkUnit(plotsHills[0][0], {})
    local resultHills = Pathfinder.findPath(unitHills, plotsHills[2][0])
    T.eq(resultHills.turns, 2, "grass-hill should take two turns with 2 MP unit")
end

-- 3. Inca FasterInHills trait cancels the surcharge. Same grid as (2)
-- but a trait flag injected via GameInfo.Traits row; the hill path now
-- fits in one turn again.
function M.test_inca_faster_in_hills_cancels_surcharge()
    setup()
    GameInfo.Leaders = { [0] = { Type = "LEADER_PACHACUTI" } }
    GameInfo.Traits = {
        TRAIT_GREAT_ANDEAN_ROAD = { FasterInHills = true },
    }
    GameInfo.Leader_Traits = function()
        local rows = { { LeaderType = "LEADER_PACHACUTI", TraitType = "TRAIT_GREAT_ANDEAN_ROAD" } }
        local i = 0
        return function()
            i = i + 1
            return rows[i]
        end
    end
    local plots = installGrid(4, function(col, row, p)
        if col == 2 and row == 0 then
            p._isHills = true
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {})
    Players[0].GetLeaderType = function()
        return 0
    end
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.turns, 1, "Inca unit should cross hills without surcharge")
end

-- 4. Forest feature overrides grass base. A single forest step costs
-- 120 MP (2 * 60); a 4 MP unit spends 120 of 240 on the step and still
-- has 120 left, so the move fits in one turn. The cost check isolates
-- the feature override (grass alone would have cost 60).
function M.test_forest_overrides_grass_base_cost()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._feature = FEAT_FOREST
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], { maxMoves = 240 })
    local result = Pathfinder.findPath(unit, plots[1][0])
    T.eq(result.mpCost, 120, "forest step should cost 120 MP (2 * 60)")
    T.eq(result.turns, 1, "4-MP unit finishes forest step within one turn")
end

-- 5. Road-to-road reduces cost. Two-hex path with road on both endpoints
-- costs routeFlat * baseMoves (10 * 2 = 20 per step). Compare with the
-- same path sans-road (60 per step) to show the discount applies.
function M.test_road_reduces_mp_cost()
    setup()
    local plotsNoRoad = installGrid(4)
    local unitNoRoad = mkUnit(plotsNoRoad[0][0], {})
    local resultNoRoad = Pathfinder.findPath(unitNoRoad, plotsNoRoad[2][0])
    T.eq(resultNoRoad.mpCost, 120, "baseline grass-grass = 120 in 60ths")

    setup()
    local plotsRoad = installGrid(4, function(col, row, p)
        if row == 0 and col >= 0 and col <= 2 then
            p._route = ROUTE_ROAD
        end
        return p
    end)
    local unitRoad = mkUnit(plotsRoad[0][0], {})
    local resultRoad = Pathfinder.findPath(unitRoad, plotsRoad[2][0])
    T.truthy(resultRoad.mpCost < resultNoRoad.mpCost, "road path must cost less")
    T.eq(resultRoad.mpCost, 40, "road-road = 2 * (10 * 2) = 40 in 60ths")
end

-- 6. Pillaged road disables the discount. One plot in the corridor has
-- IsRoutePillaged=true, so the pair for that step falls back to terrain
-- cost. Round-trip cost returns to the non-road baseline.
function M.test_pillaged_road_disables_discount()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if row == 0 and col >= 0 and col <= 2 then
            p._route = ROUTE_ROAD
            if col == 1 then
                p._isRoutePillaged = true
            end
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {})
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.mpCost, 120, "pillaged road should cost like grass: 2 * 60 = 120")
end

-- 7. River crossing ends turn without Engineering / Amphibious; permits
-- with either. Using IsRiverCrossingToPlot stub to avoid parity work on
-- the per-edge river flags.
function M.test_river_crossing_ends_turn_without_engineering()
    setup()
    local plots = installGrid(4)
    plots[0][0]._riverCrossings[plots[1][0]] = true
    plots[1][0]._riverCrossings[plots[0][0]] = true
    local unit = mkUnit(plots[0][0], {})
    local result = Pathfinder.findPath(unit, plots[1][0])
    T.eq(result.turns, 1, "the end-turn move itself still completes in one turn")
    -- Second-hex target forces a second turn since the first step ate the turn.
    local result2 = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result2.turns, 2, "river-then-grass should take two turns")
end

function M.test_engineering_skips_river_penalty()
    setup()
    local plots = installGrid(4)
    plots[0][0]._riverCrossings[plots[1][0]] = true
    plots[1][0]._riverCrossings[plots[0][0]] = true
    local unit = mkUnit(plots[0][0], { techs = { [TECH_ENGINEERING] = true } })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.turns, 1, "Engineering bypasses the river end-turn")
end

-- River end-turn after the unit already drained its MP on prior tiles.
-- 2-MP unit, 3-hex path (grass, grass, river): steps 1-2 exhaust turn 1,
-- so the river step can't land until turn 2 (where it ends that turn
-- too). Regression test for an early advance() version that skipped the
-- "waiting" turn when endsTurn fired at mpRemaining == 0.
function M.test_river_ends_turn_even_after_mp_drained()
    setup()
    local plots = installGrid(4)
    -- River between (2, 0) and (3, 0). A 2-MP unit taking the east
    -- corridor exhausts its turn 1 MP on hexes 1 and 2, then has to
    -- wait out the turn boundary before the river crossing (which
    -- itself eats turn 2). Baseline 3-hex grass path also takes 2
    -- turns, so both paths are equal-turn; the distinguishing signal
    -- is that the MP-exhausted river case must NOT round down to 1.
    plots[2][0]._riverCrossings[plots[3][0]] = true
    plots[3][0]._riverCrossings[plots[2][0]] = true
    local unit = mkUnit(plots[0][0], {})
    local result = Pathfinder.findPath(unit, plots[3][0])
    T.eq(result.turns, 2, "river at the end of an MP-exhausted path should take two turns")
end

function M.test_amphibious_promotion_skips_river_penalty()
    setup()
    local plots = installGrid(4)
    plots[0][0]._riverCrossings[plots[1][0]] = true
    plots[1][0]._riverCrossings[plots[0][0]] = true
    local unit = mkUnit(plots[0][0], { promotions = { [PROMOTION_AMPHIBIOUS] = true } })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.turns, 1, "Amphibious promotion bypasses the river end-turn")
end

-- 8. Mountain is impassable for land units, passable (but end-turn) for
-- Carthage, and straight-line for hover units. Grid: a single mountain
-- plot at (1,0) between origin and (2,0) forces either a detour or a
-- trait-dependent override.
function M.test_mountain_impassable_for_land_unit()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {})
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "there must still be a detour around the mountain")
    T.truthy(result.mpCost > 120, "detour should cost more than the direct two-hex path")
end

function M.test_hover_unit_ignores_mountain()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {
        domain = DomainTypes.DOMAIN_HOVER,
        promotions = { [PROMOTION_HOVERING_UNIT] = true },
    })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.mpCost, 120, "hover straight-lines through mountain at 60/hex")
end

function M.test_carthage_crosses_mountain_with_end_turn()
    setup()
    GameInfo.Leaders = { [0] = { Type = "LEADER_DIDO" } }
    GameInfo.Traits = { TRAIT_PHOENICIAN_HERITAGE = { CrossesMountainsAfterGreatGeneral = true } }
    GameInfo.Leader_Traits = function()
        local rows = { { LeaderType = "LEADER_DIDO", TraitType = "TRAIT_PHOENICIAN_HERITAGE" } }
        local i = 0
        return function()
            i = i + 1
            return rows[i]
        end
    end
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {})
    Players[0].GetLeaderType = function()
        return 0
    end
    local result = Pathfinder.findPath(unit, plots[1][0])
    T.eq(result.turns, 1, "Carthage mountain crossing itself is one turn")
    local result2 = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result2.turns, 2, "second hex after mountain should push into next turn")
end

-- 9. Closed enemy borders reject the step. Direct path through an enemy
-- tile must detour around it.
function M.test_closed_borders_block_path()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._owner = 1
        end
        return p
    end)
    Players[1] = {
        _team = 1,
        GetTeam = function()
            return 1
        end,
        IsAlive = function()
            return true
        end,
        GetBuildingClassCount = function()
            return 0
        end,
        Units = function()
            return function()
                return nil
            end
        end,
    }
    Teams[1] = T.fakeTeam({})
    local unit = mkUnit(plots[0][0], {})
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "a detour must exist")
    T.truthy(result.mpCost > 120, "detour must cost more than the direct 2-hex path")
end

-- 10. Great Wall border entry ends turn. Enemy owner holds the wonder;
-- stepping onto an owned plot consumes the whole turn. Compare against
-- an otherwise-equivalent enemy tile without the wonder.
function M.test_great_wall_tile_ends_turn()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._owner = 1
        end
        return p
    end)
    Players[1] = {
        _team = 1,
        GetTeam = function()
            return 1
        end,
        IsAlive = function()
            return true
        end,
        GetBuildingClassCount = function(_, cls)
            return cls == BUILDINGCLASS_GREAT_WALL and 1 or 0
        end,
        Units = function()
            return function()
                return nil
            end
        end,
    }
    Teams[0] = T.fakeTeam({ atWar = { [1] = true } })
    Teams[1] = T.fakeTeam({ atWar = { [0] = true } })
    local unit = mkUnit(plots[0][0], {})
    -- Reinstall team after mkUnit so war flags aren't overwritten.
    Teams[0] = T.fakeTeam({ atWar = { [1] = true } })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "wall tile should still be enterable, just end turn")
    T.eq(result.turns, 2, "entering Great Wall tile ends turn, next hex = turn 2")
end

-- 11. ZoC-adjacent entry ends turn. Use a 4-MP cavalry-shaped unit
-- over a two-hex corridor so the baseline finishes in one turn, and
-- the ZoC end-turn on entering (1, 0) from (0, 0) forces a second
-- turn even though only two hexes worth of MP are needed. Everything
-- off row 0 is a mountain (the enemy plot excepted) to block detours.
function M.test_zoc_entry_ends_turn()
    local function installCorridor()
        return installGrid(4, function(col, row, p)
            if row ~= 0 and not (col == 1 and row == 1) then
                -- Block every tile off row 0 except the enemy's plot.
                p._isMountain = true
            end
            return p
        end)
    end

    setup()
    local plotsBase = installCorridor()
    local unitBase = mkUnit(plotsBase[0][0], { maxMoves = 240 })
    local baseline = Pathfinder.findPath(unitBase, plotsBase[2][0])
    T.truthy(baseline ~= nil, "corridor baseline should be reachable")
    T.eq(baseline.turns, 1, "2 grass hexes at 4 MP should finish in one turn")

    setup()
    local plots = installCorridor()
    local enemyPlot = plots[1][1]
    enemyPlot._isMountain = false
    local enemyUnit = T.fakeUnit({ owner = 1, team = 1, combat = true, invisible = false })
    enemyUnit._plot = enemyPlot
    Players[1] = {
        _team = 1,
        GetTeam = function()
            return 1
        end,
        IsAlive = function()
            return true
        end,
        GetBuildingClassCount = function()
            return 0
        end,
        Units = function()
            local sent = false
            return function()
                if sent then
                    return nil
                end
                sent = true
                return enemyUnit
            end
        end,
    }
    Teams[1] = T.fakeTeam({ atWar = { [0] = true } })
    local unit = mkUnit(plots[0][0], { maxMoves = 240 })
    Teams[0] = T.fakeTeam({ atWar = { [1] = true } })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "corridor with ZoC must still be pathable")
    T.truthy(result.turns > baseline.turns, "ZoC entry must add at least one turn; got "
        .. tostring(result.turns) .. " vs baseline " .. tostring(baseline.turns))
end

-- 12. Embarkation: land unit entering water ends turn; with flat-cost
-- promotion it's one MP instead.
function M.test_embarkation_ends_turn_without_flat_cost()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col >= 1 then
            p._isWater = true
            p._terrain = TERRAIN_COAST
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], { canEmbark = true })
    local result = Pathfinder.findPath(unit, plots[1][0])
    T.eq(result.turns, 1, "the embark step itself fits in the current turn")
    local result2 = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result2.turns, 2, "embark + second water hex spans two turns")
end

function M.test_embarkation_flat_cost_promotion()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col >= 1 then
            p._isWater = true
            p._terrain = TERRAIN_COAST
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {
        canEmbark = true,
        promotions = { [PROMOTION_FLAT_MOVEMENT_COST] = true },
    })
    local result = Pathfinder.findPath(unit, plots[2][0])
    T.eq(result.turns, 1, "flat-cost promotion keeps embark + water step in one turn")
end

-- 13. Polynesia's EmbarkedAllWater trait permits water entry before
-- Optics. Absence of canEmbark would normally reject the step; the
-- trait flips ctx.canEmbark.
function M.test_polynesia_starts_embarked_without_optics()
    setup()
    GameInfo.Leaders = { [0] = { Type = "LEADER_KAMEHAMEHA" } }
    GameInfo.Traits = { TRAIT_WAYFINDING = { EmbarkedAllWater = true } }
    GameInfo.Leader_Traits = function()
        local rows = { { LeaderType = "LEADER_KAMEHAMEHA", TraitType = "TRAIT_WAYFINDING" } }
        local i = 0
        return function()
            i = i + 1
            return rows[i]
        end
    end
    local plots = installGrid(4, function(col, row, p)
        if col >= 1 then
            p._isWater = true
            p._terrain = TERRAIN_COAST
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], { canEmbark = false })
    Players[0].GetLeaderType = function()
        return 0
    end
    local result, reason = Pathfinder.findPath(unit, plots[1][0])
    T.truthy(result ~= nil, "Polynesia should path into coast without Optics: " .. tostring(reason))
end

-- 14. Fully-impassable surround returns unreachable. Target ringed by
-- mountains; a non-hover land unit cannot enter.
function M.test_unreachable_target_returns_reason()
    setup()
    local plots = installGrid(3, function(col, row, p)
        -- Mountain ring around (2, 0).
        if (col == 1 and row == 0) or (col == 3 and row == 0) or (col == 2 and row == -1) or (col == 2 and row == 1) then
            p._isMountain = true
        end
        -- Also block diagonal neighbors so the odd-row offsets don't
        -- accidentally leave a gap through (even vs. odd row parity
        -- gives six unique neighbors; mount them all).
        if col == 2 and (row == -1 or row == 1) then
            p._isMountain = true
        end
        if col == 1 and (row == -1 or row == 1) then
            p._isMountain = true
        end
        if col == 3 and (row == -1 or row == 1) then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkUnit(plots[0][0], {})
    local result, reason = Pathfinder.findPath(unit, plots[2][0])
    T.truthy(result == nil, "surrounded target must be unreachable")
    T.eq(reason, "unreachable")
end

return M
