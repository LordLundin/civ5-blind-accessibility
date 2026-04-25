-- RoutePathfinder: A* mirroring vanilla BuildRouteCost / BuildRouteValid
-- (CvAStar.cpp:2493-2596). Each test exercises a distinct rule branch
-- of the cost / validity functions, plus the per-tile build-turn sum.

local T = require("support")
local M = {}

local TERRAIN_GRASS = 1
local TERRAIN_FOREST = 2
local TERRAIN_COAST = 3
local FEAT_FOREST = 1
local FEAT_MARSH = 2
local ROUTE_ROAD = 0
local ROUTE_RAILROAD = 1
local TECH_THE_WHEEL = 10
local TECH_RAILROAD = 11
local BUILD_ROAD = 100
local BUILD_RAILROAD = 101

-- A build's GetBuildTurnsLeft is read out of plot._buildTurns by the
-- fakePlot helper. Default 3 turns per BUILD_ROAD on grass mirrors base
-- XML; tests that exercise terrain-modifier branches override per-plot.
local function defaultBuildTurns(buildId)
    if buildId == BUILD_ROAD then
        return 3
    end
    if buildId == BUILD_RAILROAD then
        return 4
    end
    return 0
end

local function setup(opts)
    opts = opts or {}
    dofile("src/dlc/UI/InGame/CivVAccess_RoutePathfinder.lua")

    GameInfoTypes = {
        TECH_THE_WHEEL = TECH_THE_WHEEL,
        TECH_RAILROAD = TECH_RAILROAD,
        ROUTE_ROAD = ROUTE_ROAD,
        ROUTE_RAILROAD = ROUTE_RAILROAD,
    }

    local builds = {
        {
            ID = BUILD_ROAD,
            Type = "BUILD_ROAD",
            RouteType = "ROUTE_ROAD",
            PrereqTech = "TECH_THE_WHEEL",
        },
    }
    if opts.includeRailroad then
        builds[#builds + 1] = {
            ID = BUILD_RAILROAD,
            Type = "BUILD_RAILROAD",
            RouteType = "ROUTE_RAILROAD",
            PrereqTech = "TECH_RAILROAD",
        }
    end

    GameInfo = {
        Terrains = {
            [TERRAIN_GRASS] = { Type = "TERRAIN_GRASS", Movement = 1 },
            [TERRAIN_FOREST] = { Type = "TERRAIN_FOREST", Movement = 1 },
            [TERRAIN_COAST] = { Type = "TERRAIN_COAST", Movement = 1 },
        },
        Features = {
            [FEAT_FOREST] = { Type = "FEATURE_FOREST", Movement = 2 },
            [FEAT_MARSH] = { Type = "FEATURE_MARSH", Movement = 3 },
        },
        Routes = {
            [ROUTE_ROAD] = { Type = "ROUTE_ROAD", Value = 1, FlatMovement = 30 },
            [ROUTE_RAILROAD] = { Type = "ROUTE_RAILROAD", Value = 2, FlatMovement = 6 },
        },
        Builds = function()
            local i = 0
            return function()
                i = i + 1
                return builds[i]
            end
        end,
    }

    Players = {}
    Teams = {}
end

-- Hex grid identical to suite_pathfinder.lua's installGrid, minus the
-- ZoC corridor helper. Configure callback can override a plot or seed
-- buildTurns per buildId.
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
                buildTurns = {
                    [BUILD_ROAD] = defaultBuildTurns(BUILD_ROAD),
                    [BUILD_RAILROAD] = defaultBuildTurns(BUILD_RAILROAD),
                },
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
    return plots
end

local function mkWorker(plot, opts)
    opts = opts or {}
    local unit = T.fakeUnit({
        owner = 0,
        team = 0,
        domain = DomainTypes.DOMAIN_LAND,
        maxMoves = 120,
        movesLeft = 120,
    })
    unit._plot = plot
    function unit:WorkRate(_, _)
        return opts.workRate or 100
    end
    Teams[0] = T.fakeTeam({
        techs = opts.techs or { [TECH_THE_WHEEL] = true },
    })
    Players[0] = {
        GetTeam = function()
            return 0
        end,
        IsAlive = function()
            return true
        end,
    }
    return unit
end

-- ===== Tests =====

-- 1. Straight-line open grass: tile count is the 3 hexes the worker
-- walks INTO (excluding the start plot); build turns is the sum across
-- all 4 plots in the chain including the start, since the engine fires
-- UnitBuild on the start plot too if it needs a route.
function M.test_straight_line_grass_path()
    setup()
    local plots = installGrid(4)
    local unit = mkWorker(plots[0][0])
    local result, reason = RoutePathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil, "expected path: " .. tostring(reason))
    T.eq(result.tileCount, 3, "3 tiles east, excluding the start plot")
    T.eq(result.buildTurns, 12, "4 plots * 3 BUILD_ROAD turns each")
    T.eq(result.buildId, BUILD_ROAD, "should pick BUILD_ROAD when only TECH_THE_WHEEL is researched")
end

-- 2. Existing route on a tile contributes zero build turns. Place road
-- on the middle tile and confirm the turn sum drops by one tile's worth.
function M.test_existing_route_skips_build()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._route = ROUTE_ROAD
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil)
    T.eq(result.tileCount, 3, "tile count unchanged: existing route is still in the path")
    T.eq(result.buildTurns, 9, "3 plots * 3 turns; the routed plot contributes 0")
end

-- 3. Railroad upgrades over existing road. Player has TECH_RAILROAD; the
-- target plot has a road; the engine queues BUILD_RAILROAD and the road
-- tile gets a railroad turn count, NOT skipped.
function M.test_railroad_upgrades_road_tile()
    setup({ includeRailroad = true })
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._route = ROUTE_ROAD
        end
        return p
    end)
    local unit = mkWorker(plots[0][0], { techs = { [TECH_THE_WHEEL] = true, [TECH_RAILROAD] = true } })
    local result = RoutePathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil)
    T.eq(result.buildId, BUILD_RAILROAD, "should pick BUILD_RAILROAD with TECH_RAILROAD")
    T.eq(result.buildTurns, 16, "4 plots * 4 BUILD_RAILROAD turns; road tile still needs railroad upgrade")
end

-- 4. Railroad over existing railroad: plot already at target tier, skip.
function M.test_existing_railroad_skips_when_target_is_railroad()
    setup({ includeRailroad = true })
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._route = ROUTE_RAILROAD
        end
        return p
    end)
    local unit = mkWorker(plots[0][0], { techs = { [TECH_THE_WHEEL] = true, [TECH_RAILROAD] = true } })
    local result = RoutePathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil)
    T.eq(result.buildTurns, 12, "3 plots * 4 turns; existing-railroad plot contributes 0")
end

-- 5. Cities count as connection nodes; the worker's auto-route does not
-- build a road on a city tile. A path through the player's own city
-- should subtract that tile's build turns.
function M.test_city_tile_skipped()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isCity = true
            p._owner = 0
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[3][0])
    T.truthy(result ~= nil)
    T.eq(result.buildTurns, 9, "3 non-city plots * 3 turns; city contributes 0")
end

-- 6. Mountain in the direct path forces a detour. Result is non-nil
-- (longer path exists) but tile count exceeds the straight-line minimum.
function M.test_mountain_forces_detour()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "detour around mountain must exist")
    T.truthy(result.tileCount > 2, "detour adds tiles; got " .. tostring(result.tileCount))
end

-- 7. Foreign closed-borders territory rejects the path. A two-tile
-- direct path runs through an enemy-owned plot; with no OB the route
-- pathfinder rejects every step that crosses the border. A detour
-- around exists in this grid (row +/-1 is open).
function M.test_foreign_closed_borders_blocks()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._owner = 1
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "detour around closed-border tile must exist")
    T.truthy(result.tileCount > 2, "must detour, not transit foreign territory")
end

-- 8. Foreign owner with friendly-territory grant (OB) permits transit.
function M.test_foreign_open_borders_permits_transit()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._owner = 1
        end
        return p
    end)
    -- Override IsFriendlyTerritory on the foreign plot to return true
    -- for player 0 (simulating an OB grant); the support helper reads
    -- this off opts.isFriendlyTerritory but we re-built the plot with
    -- defaults, so monkey-patch the method directly.
    plots[1][0].IsFriendlyTerritory = function(_, player)
        return player == 0
    end
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil)
    T.eq(result.tileCount, 2, "OB-friendly tile lets the straight 2-hex path through")
end

-- 9. Water plots reject (route can only run on land).
function M.test_water_plot_blocks()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if col == 1 and row == 0 then
            p._isWater = true
            p._terrain = TERRAIN_COAST
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil, "detour around water must exist")
    T.truthy(result.tileCount > 2, "must avoid water step")
end

-- 10. stepCost matches CvAStar.cpp:2493-2533 BuildRouteCost arithmetic.
-- Existing route returns 10. No-route grass (move cost 1) returns
-- 1500/2 + 1500/2 = 1500. Forest (feature cost 2) returns
-- 750 + 1500/3 = 1250. Marsh (feature cost 3) returns 750 + 1500/4 = 1125.
function M.test_step_cost_matches_engine_formula()
    setup()
    local grass = T.fakePlot({ terrain = TERRAIN_GRASS })
    T.eq(RoutePathfinder._stepCost(grass), 1500, "grass: 750 + 1500/2 = 1500")
    local forest = T.fakePlot({ terrain = TERRAIN_GRASS, feature = FEAT_FOREST })
    T.eq(RoutePathfinder._stepCost(forest), 1250, "forest: 750 + 1500/3 = 1250")
    local marsh = T.fakePlot({ terrain = TERRAIN_GRASS, feature = FEAT_MARSH })
    T.eq(RoutePathfinder._stepCost(marsh), 1125, "marsh: 750 + 1500/4 = 1125")
    local roaded = T.fakePlot({ terrain = TERRAIN_GRASS, route = ROUTE_ROAD })
    T.eq(RoutePathfinder._stepCost(roaded), 10, "existing route returns EXISTING_ROUTE_WEIGHT")
end

-- 11. Same plot returns same_plot reason.
function M.test_same_plot_destination()
    setup()
    local plots = installGrid(2)
    local unit = mkWorker(plots[0][0])
    local result, reason = RoutePathfinder.findPath(unit, plots[0][0])
    T.truthy(result == nil)
    T.eq(reason, "same_plot")
end

-- 12. Unrevealed destination short-circuits to "unexplored".
function M.test_unexplored_destination()
    setup()
    local plots = installGrid(2, function(col, row, p)
        if col == 1 and row == 0 then
            p._isRevealed = false
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result, reason = RoutePathfinder.findPath(unit, plots[1][0])
    T.truthy(result == nil)
    T.eq(reason, "unexplored")
end

-- 13. Surrounded destination returns "unreachable".
function M.test_unreachable_destination()
    setup()
    local plots = installGrid(3, function(col, row, p)
        local d = math.max(math.abs(col - 2), math.abs(row))
        if d == 1 then
            p._isMountain = true
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result, reason = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result == nil)
    T.eq(reason, "unreachable")
end

-- 14. No build available: player without TECH_THE_WHEEL has no buildable
-- route. Returns "no_build" reason.
function M.test_no_build_when_no_tech()
    setup()
    local plots = installGrid(2)
    local unit = mkWorker(plots[0][0], { techs = {} })
    local result, reason = RoutePathfinder.findPath(unit, plots[1][0])
    T.truthy(result == nil)
    T.eq(reason, "no_build")
end

-- 15. Path the worker fully covers in already-routed tiles: tile count
-- positive but build turns = 0. The mission completes the moment the
-- worker walks the chain (engine's GetBestBuildRouteForRoadTo returns
-- NO_ROUTE on every tile because they're already at the target tier).
function M.test_already_done_when_full_path_routed()
    setup()
    local plots = installGrid(4, function(col, row, p)
        if row == 0 and col >= 0 and col <= 2 then
            p._route = ROUTE_ROAD
        end
        return p
    end)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil)
    T.eq(result.tileCount, 2)
    T.eq(result.buildTurns, 0, "fully routed path needs no build work")
end

-- 16. Returned plots list orders start to goal inclusive.
function M.test_path_plots_ordered_start_to_goal()
    setup()
    local plots = installGrid(2)
    local unit = mkWorker(plots[0][0])
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil)
    T.eq(result.plots[1]._x, 0, "first plot is the worker's start")
    T.eq(result.plots[#result.plots]._x, 2, "last plot is the destination")
    T.eq(#result.plots, result.tileCount + 1, "plots includes the start; tileCount excludes it")
end

-- 17. Start plot extra-rate zero-out. When the worker is currently
-- mid-build of the same route type on their own plot, the engine's
-- tooltip pattern passes 0 as extraRate for that plot to avoid double-
-- counting the rate already baked into the plot's existing progress.
-- Other plots in the chain still get the worker's full work rate.
function M.test_start_plot_extra_rate_zero_when_mid_build()
    setup()
    local plots = installGrid(2)
    local unit = mkWorker(plots[0][0])
    unit._buildType = BUILD_ROAD
    -- Capture (extraNow, extraThen) per plotIndex so we can assert what
    -- was passed.
    local captured = {}
    for col = -2, 2 do
        for row = -2, 2 do
            local p = plots[col][row]
            local idx = p:GetPlotIndex()
            p.GetBuildTurnsLeft = function(self, _build, _player, extraNow, extraThen)
                captured[idx] = { extraNow, extraThen }
                return 3
            end
        end
    end
    local result = RoutePathfinder.findPath(unit, plots[2][0])
    T.truthy(result ~= nil)
    local startIdx = plots[0][0]:GetPlotIndex()
    local laterIdx = plots[2][0]:GetPlotIndex()
    T.eq(captured[startIdx][1], 0, "start plot mid-build of same buildId should pass extra=0")
    T.truthy(captured[laterIdx][1] > 0, "non-start plots should get the worker's work rate")
end

-- 18. Worker NOT mid-build: every plot in the chain gets the worker's
-- work rate, including the start plot. Mirror of 17 with _buildType=-1.
function M.test_all_plots_get_work_rate_when_idle()
    setup()
    local plots = installGrid(2)
    local unit = mkWorker(plots[0][0])
    -- _buildType defaults to -1 in fakeUnit; explicit for clarity.
    unit._buildType = -1
    local captured = {}
    for col = -2, 2 do
        for row = -2, 2 do
            local p = plots[col][row]
            local idx = p:GetPlotIndex()
            p.GetBuildTurnsLeft = function(self, _build, _player, extraNow, _extraThen)
                captured[idx] = extraNow
                return 3
            end
        end
    end
    RoutePathfinder.findPath(unit, plots[2][0])
    local startIdx = plots[0][0]:GetPlotIndex()
    T.truthy(captured[startIdx] > 0, "idle worker's start plot should get work rate")
end

return M
