-- Tests for the PlotAudio mapping + dispatch. cueForPlot is pure (plot
-- handle in, cue table out) so most tests just assert the returned shape.
-- emit tests use the capturing audio stub from run.lua to observe call
-- order and arguments.

local T = require("support")
local M = {}

local function setup()
    dofile("src/dlc/UI/InGame/CivVAccess_PlotAudio.lua")

    Game.GetActiveTeam = function()
        return 0
    end
    Game.IsDebugMode = function()
        return false
    end

    GameInfo = {}
    GameInfo.Terrains = {}
    GameInfo.Features = {}

    audio._reset()
    civvaccess_shared.plotAudioHandles = nil
end

-- Helper: install feature / terrain row pairs in one line.
local function feature(id, typeName, extra)
    local row = { Type = typeName }
    if extra then
        for k, v in pairs(extra) do
            row[k] = v
        end
    end
    GameInfo.Features[id] = row
end

local function terrain(id, typeName)
    GameInfo.Terrains[id] = { Type = typeName }
end

-- ===== cueForPlot: reveal gating =====

function M.test_cueForPlot_unrevealed_returns_nil()
    -- Unrevealed plots have no audio representation; caller decides how to
    -- handle them (current caller speaks "unexplored" and skips emit).
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ revealed = false, terrain = 0 })
    T.eq(PlotAudio.cueForPlot(p), nil)
end

-- ===== cueForPlot: bed priority =====

function M.test_cueForPlot_mountain_outranks_feature_and_terrain()
    -- Mountain is priority 1: it sounds categorically different and sits
    -- outside the flat-vs-elevated axis. Even a promotable feature on a
    -- mountain plot must resolve to the mountain bed.
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(1, "FEATURE_JUNGLE")
    local p = T.fakePlot({ mountain = true, terrain = 0, feature = 1 })
    T.eq(PlotAudio.cueForPlot(p).bed, "mountain")
end

function M.test_cueForPlot_promotable_feature_replaces_terrain_bed()
    -- Priority 2: a promotable feature (jungle, marsh, ...) replaces the
    -- base-terrain bed because the feature's sonic character dominates and
    -- the feature has exactly one allowed base terrain.
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(1, "FEATURE_JUNGLE")
    local p = T.fakePlot({ terrain = 0, feature = 1 })
    T.eq(PlotAudio.cueForPlot(p).bed, "jungle")
end

function M.test_cueForPlot_natural_wonder_does_not_promote_to_feature_bed()
    -- Natural wonders are speech-only (no dedicated wonder sound in the
    -- palette). The cue bed must come from the underlying mountain/terrain;
    -- wonder identity is spoken by the cursor pipeline separately.
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(9, "FEATURE_FUJI", { NaturalWonder = true })
    -- Mountain-class wonder: Natural_Wonder_Placement rewrites the core to
    -- mountain, so plot:IsMountain() returns true.
    local p = T.fakePlot({ mountain = true, terrain = 0, feature = 9 })
    T.eq(PlotAudio.cueForPlot(p).bed, "mountain")
end

function M.test_cueForPlot_natural_wonder_on_flat_falls_through_to_terrain()
    -- A handful of wonders are flat (e.g. Mt. Kailash equivalents placed on
    -- plains). With IsMountain false and wonder not promoting, the plot's
    -- base-terrain bed plays underneath.
    setup()
    terrain(2, "TERRAIN_PLAINS")
    feature(9, "FEATURE_FOUNTAIN_OF_YOUTH", { NaturalWonder = true })
    local p = T.fakePlot({ terrain = 2, feature = 9 })
    T.eq(PlotAudio.cueForPlot(p).bed, "plains")
end

function M.test_cueForPlot_stinger_feature_does_not_promote_to_bed()
    -- Forest is a stinger, not a bed: it spans grass / plains / tundra,
    -- any of which is the distinguishing fact. Bed must come from the
    -- underlying terrain and forest must appear in stingers.
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(6, "FEATURE_FOREST")
    local p = T.fakePlot({ terrain = 0, feature = 6 })
    local cue = PlotAudio.cueForPlot(p)
    T.eq(cue.bed, "grassland")
    T.eq(cue.stingers[1], "forest")
end

function M.test_cueForPlot_terrain_bed_grass()
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ terrain = 0 })
    T.eq(PlotAudio.cueForPlot(p).bed, "grassland")
end

function M.test_cueForPlot_coast_and_ocean_collapse_to_water_bed()
    -- Plan section 2.5: coast / ocean / lake share sonic character and the
    -- engine's ambient already differentiates them.
    setup()
    terrain(5, "TERRAIN_COAST")
    terrain(6, "TERRAIN_OCEAN")
    local coastPlot = T.fakePlot({ terrain = 5 })
    local oceanPlot = T.fakePlot({ terrain = 6 })
    T.eq(PlotAudio.cueForPlot(coastPlot).bed, "water")
    T.eq(PlotAudio.cueForPlot(oceanPlot).bed, "water")
end

function M.test_cueForPlot_lake_resolves_to_water_even_without_known_terrain()
    -- IsLake defensive fallback: lake is not its own terrain type. If the
    -- terrain doesn't map cleanly, IsLake forces water.
    setup()
    -- Deliberately no TERRAIN_LAKE entry; leave terrain as an unknown id.
    local p = T.fakePlot({ terrain = 99, lake = true })
    T.eq(PlotAudio.cueForPlot(p).bed, "water")
end

function M.test_cueForPlot_ice_feature_replaces_water_bed()
    -- Ice is a promotable feature layered on water terrain. The bed flips
    -- to ice; the water bed is suppressed.
    setup()
    terrain(5, "TERRAIN_COAST")
    feature(1, "FEATURE_ICE")
    local p = T.fakePlot({ terrain = 5, feature = 1 })
    T.eq(PlotAudio.cueForPlot(p).bed, "ice")
end

-- ===== cueForPlot: fog wash =====

function M.test_cueForPlot_fog_true_when_revealed_but_not_visible()
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ revealed = true, visible = false, terrain = 0 })
    T.eq(PlotAudio.cueForPlot(p).fog, true)
end

function M.test_cueForPlot_fog_false_when_fully_visible()
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ revealed = true, visible = true, terrain = 0 })
    T.eq(PlotAudio.cueForPlot(p).fog, false)
end

-- ===== cueForPlot: stingers =====

function M.test_cueForPlot_forest_stinger_fires_independently_of_terrain()
    -- Forest on plains produces stingers = { forest }, bed = plains.
    setup()
    terrain(2, "TERRAIN_PLAINS")
    feature(6, "FEATURE_FOREST")
    local p = T.fakePlot({ terrain = 2, feature = 6 })
    local cue = PlotAudio.cueForPlot(p)
    T.eq(cue.bed, "plains")
    T.eq(#cue.stingers, 1)
    T.eq(cue.stingers[1], "forest")
end

function M.test_cueForPlot_fallout_stinger_on_any_terrain()
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(7, "FEATURE_FALLOUT")
    local p = T.fakePlot({ terrain = 0, feature = 7 })
    local cue = PlotAudio.cueForPlot(p)
    T.eq(#cue.stingers, 1)
    T.eq(cue.stingers[1], "fallout")
end

function M.test_cueForPlot_road_stinger_when_route_present()
    -- Route id >= 0 means some road/railroad is built. Type distinction
    -- (road vs railroad) isn't in the palette; a single stinger covers
    -- both.
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ terrain = 0, route = 0 })
    local cue = PlotAudio.cueForPlot(p)
    T.eq(#cue.stingers, 1)
    T.eq(cue.stingers[1], "road")
end

function M.test_cueForPlot_forest_and_road_coexist_in_stingers()
    -- Stingers are independent axes: forest feature + a road layered on
    -- top produce both.
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(6, "FEATURE_FOREST")
    local p = T.fakePlot({ terrain = 0, feature = 6, route = 0 })
    local cue = PlotAudio.cueForPlot(p)
    T.eq(#cue.stingers, 2)
    -- Check set membership since order within stingers is not load-bearing.
    local names = {}
    for _, s in ipairs(cue.stingers) do
        names[s] = true
    end
    T.truthy(names.forest, "forest must be in stingers")
    T.truthy(names.road, "road must be in stingers")
end

function M.test_cueForPlot_no_route_means_no_road_stinger()
    setup()
    terrain(0, "TERRAIN_GRASS")
    local p = T.fakePlot({ terrain = 0, route = -1 })
    T.eq(#PlotAudio.cueForPlot(p).stingers, 0)
end

-- ===== emit: dispatch ordering =====
-- emit pulls handles out of civvaccess_shared.plotAudioHandles (populated
-- by loadAll). Tests run loadAll in setup so emit has something to call.

local function opNames(calls)
    local out = {}
    for _, c in ipairs(calls) do
        out[#out + 1] = c.op
    end
    return out
end

function M.test_emit_cancel_all_fires_before_any_play()
    -- Plan section 4.3: every cursor move cancels all in-flight audio
    -- before starting the new cue. The cancel must come first or the new
    -- bed would briefly play alongside the prior cue.
    setup()
    terrain(0, "TERRAIN_GRASS")
    PlotAudio.loadAll()
    audio._reset() -- discard the load calls so op indices are predictable

    local p = T.fakePlot({ terrain = 0, revealed = true, visible = true })
    PlotAudio.emit(p)

    T.truthy(#audio._calls >= 1, "emit must produce at least one call")
    T.eq(audio._calls[1].op, "cancel_all", "first op must be cancel_all")
end

function M.test_emit_plays_bed_then_stingers_delayed()
    setup()
    terrain(0, "TERRAIN_GRASS")
    feature(6, "FEATURE_FOREST")
    PlotAudio.loadAll()
    audio._reset()

    local p = T.fakePlot({ terrain = 0, feature = 6, revealed = true, visible = true })
    PlotAudio.emit(p)

    local ops = opNames(audio._calls)
    T.eq(ops[1], "cancel_all")
    T.eq(ops[2], "play", "bed plays at t=0")
    T.eq(ops[3], "play_delayed", "stinger uses play_delayed (offset onset)")
    -- The delayed stinger must carry a positive ms offset so it lands
    -- after the bed starts, not on top of it.
    T.truthy(audio._calls[3].ms > 0, "stinger offset must be > 0 ms")
end

function M.test_emit_plays_fog_alongside_bed_at_t_zero()
    -- Fog is a wash, not a stinger: it co-plays with the bed at t=0 so it
    -- reads as a tint on the bed rather than a discrete event.
    setup()
    terrain(0, "TERRAIN_GRASS")
    PlotAudio.loadAll()
    audio._reset()

    local p = T.fakePlot({ terrain = 0, revealed = true, visible = false })
    PlotAudio.emit(p)

    local ops = opNames(audio._calls)
    T.eq(ops[1], "cancel_all")
    T.eq(ops[2], "play", "bed at t=0")
    T.eq(ops[3], "play", "fog at t=0 (not play_delayed)")
end

function M.test_emit_on_unrevealed_plot_only_cancels()
    -- Unrevealed has no cue; emit still cancels in-flight audio so a prior
    -- tile's cue doesn't bleed past the move.
    setup()
    PlotAudio.loadAll()
    audio._reset()

    local p = T.fakePlot({ revealed = false })
    PlotAudio.emit(p)

    T.eq(#audio._calls, 1)
    T.eq(audio._calls[1].op, "cancel_all")
end

-- ===== loadAll: idempotency =====

function M.test_loadAll_is_idempotent_across_reentry()
    -- Boot.lua fires loadAll on LoadScreenClose. The guard in PlotAudio
    -- must suppress a second loadAll so the bank isn't burned on Context
    -- re-instantiation.
    setup()
    PlotAudio.loadAll()
    local firstCount = audio._loadCounter
    PlotAudio.loadAll()
    T.eq(audio._loadCounter, firstCount, "second loadAll must be a no-op")
end

function M.test_loadAll_sets_fog_to_half_volume()
    -- Fog wash plays at half per-sound volume so it reads as a tint on the
    -- bed rather than a discrete event. loadAll is where this lives (once
    -- at boot, persistent per sound) rather than on every emit.
    setup()
    PlotAudio.loadAll()
    local fogId = civvaccess_shared.plotAudioHandles.fog
    local found
    for _, c in ipairs(audio._calls) do
        if c.op == "set_volume" and c.id == fogId then
            found = c
            break
        end
    end
    T.truthy(found ~= nil, "loadAll must set_volume on the fog handle")
    T.eq(found.v, 0.5, "fog volume must be 0.5")
end

return M
