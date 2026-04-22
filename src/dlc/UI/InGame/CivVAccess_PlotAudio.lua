-- Plot-handle-in, cue-out mapping for the per-hex audio layer. Output shape:
-- { bed = "<name>", fog = bool, stingers = { "<name>", ... } } or nil for an
-- unrevealed plot.
--
-- PlotAudio.loadAll() preloads every sound in the palette into the proxy's
-- audio bank and stashes the name-to-handle map on civvaccess_shared so
-- re-entered Contexts reuse the existing handles (the proxy also dedups by
-- name; both guards keep the bank from filling up with duplicates).
--
-- PlotAudio.emit(plot) is the one-call dispatcher used by the cursor layer:
-- cancel in-flight audio, play bed + optional fog at t=0, fire each stinger
-- at the offset.
--
-- Natural wonders do NOT promote to a feature bed here. The bed for a
-- wonder plot comes from the plot's mountain/terrain core, and wonder
-- identity is spoken by the cursor pipeline separately (no dedicated wonder
-- sound in the palette).
--
-- See .planning/audio-cues-plan.md for the sound-palette rationale.

PlotAudio = PlotAudio or {}

-- Upper end of the plan's 50-100 ms range for stinger onset relative to
-- the bed; revisit by ear.
local STINGER_OFFSET_MS = 100

-- Fog wash plays at half per-sound volume so it reads as a tint on the bed
-- rather than a discrete event. Applied once at load via audio.set_volume
-- and inherited on every subsequent play of the fog slot.
local FOG_VOLUME = 0.5

-- Features whose bed replaces the terrain bed. Each has exactly one allowed
-- base terrain per Feature_TerrainBooleans, so the underlying terrain is
-- recoverable from the feature bed alone.
local PROMOTABLE_FEATURES = {
    FEATURE_JUNGLE       = "jungle",
    FEATURE_MARSH        = "marsh",
    FEATURE_FLOOD_PLAINS = "floodplain",
    FEATURE_OASIS        = "oasis",
    FEATURE_ICE          = "ice",
    FEATURE_ATOLL        = "atoll",
}

-- Features that layer a stinger over the bed. Forest spawns on multiple
-- base terrains; fallout on anything. Neither can serve as a bed.
local STINGER_FEATURES = {
    FEATURE_FOREST  = "forest",
    FEATURE_FALLOUT = "fallout",
}

-- Base terrain beds. Coast and ocean collapse into one water bed; lake is
-- routed here via plot:IsLake() since lake is not its own terrain type.
local TERRAIN_BEDS = {
    TERRAIN_GRASS  = "grassland",
    TERRAIN_PLAINS = "plains",
    TERRAIN_DESERT = "desert",
    TERRAIN_TUNDRA = "tundra",
    TERRAIN_SNOW   = "snow",
    TERRAIN_COAST  = "water",
    TERRAIN_OCEAN  = "water",
}

local function allSoundNames()
    local set = { mountain = true, fog = true, road = true }
    for _, v in pairs(PROMOTABLE_FEATURES) do set[v] = true end
    for _, v in pairs(STINGER_FEATURES)    do set[v] = true end
    for _, v in pairs(TERRAIN_BEDS)        do set[v] = true end
    local list = {}
    for n in pairs(set) do list[#list + 1] = n end
    return list
end

local function featureRow(plot)
    local fid = plot:GetFeatureType()
    if fid == nil or fid < 0 then return nil end
    return GameInfo.Features[fid]
end

function PlotAudio.cueForPlot(plot)
    if plot == nil then return nil end
    local team  = Game.GetActiveTeam()
    local debug = Game.IsDebugMode()
    if not plot:IsRevealed(team, debug) then
        return nil
    end

    local fRow = featureRow(plot)
    local bed

    if plot:IsMountain() then
        bed = "mountain"
    elseif fRow and not fRow.NaturalWonder then
        bed = PROMOTABLE_FEATURES[fRow.Type]
    end

    if bed == nil then
        local tid  = plot:GetTerrainType()
        local tRow = tid ~= nil and tid >= 0 and GameInfo.Terrains[tid] or nil
        bed = tRow and TERRAIN_BEDS[tRow.Type] or nil
        if bed == nil and (plot:IsLake() or plot:IsWater()) then
            bed = "water"
        end
    end

    if bed == nil then
        Log.warn("PlotAudio.cueForPlot: unresolved bed, defaulting to grassland")
        bed = "grassland"
    end

    local fog = not plot:IsVisible(team, debug)

    local stingers = {}
    if fRow then
        local stinger = STINGER_FEATURES[fRow.Type]
        if stinger ~= nil then
            stingers[#stingers + 1] = stinger
        end
    end
    local rid = plot:GetRouteType()
    if rid ~= nil and rid >= 0 then
        stingers[#stingers + 1] = "road"
    end

    return { bed = bed, fog = fog, stingers = stingers }
end

function PlotAudio.loadAll()
    if civvaccess_shared.plotAudioHandles ~= nil then return end
    if audio == nil or audio.load == nil then
        Log.warn("PlotAudio.loadAll: audio binding missing")
        return
    end
    local handles = {}
    local loaded, missed = 0, 0
    for _, name in ipairs(allSoundNames()) do
        local h = audio.load(name)
        if h == nil then
            Log.error("PlotAudio.loadAll: failed to load " .. name)
            missed = missed + 1
        else
            handles[name] = h
            loaded = loaded + 1
        end
    end
    civvaccess_shared.plotAudioHandles = handles
    if handles.fog ~= nil and audio.set_volume ~= nil then
        audio.set_volume(handles.fog, FOG_VOLUME)
    end
    Log.info("PlotAudio.loadAll: loaded " .. tostring(loaded)
             .. ", missed " .. tostring(missed))
end

local function handleFor(name)
    local h = civvaccess_shared.plotAudioHandles
    return h and h[name] or nil
end

function PlotAudio.emit(plot)
    if audio == nil then return end
    local cue = PlotAudio.cueForPlot(plot)
    audio.cancel_all()
    if cue == nil then return end

    local bedH = handleFor(cue.bed)
    if bedH ~= nil then audio.play(bedH) end
    if cue.fog then
        local fogH = handleFor("fog")
        if fogH ~= nil then audio.play(fogH) end
    end
    for _, name in ipairs(cue.stingers) do
        local h = handleFor(name)
        if h ~= nil then audio.play_delayed(h, STINGER_OFFSET_MS) end
    end
end
