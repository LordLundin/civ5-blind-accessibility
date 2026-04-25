-- Master volume for the per-hex audio cue layer. The proxy's mixer runs
-- outside the game's audio pipeline, so the engine's own volume sliders
-- don't reach our sounds. This module is the canonical access point for
-- the user-controlled volume of those cues.
--
-- VolumeControl.get() returns the live value (cached on civvaccess_shared
-- after first read so repeated reads from the Settings menu don't round-
-- trip through user data). VolumeControl.set(v) clamps to [0, 1], updates
-- the cache, persists via Prefs.setFloat, and pushes the new value into
-- the proxy via audio.set_master_volume. VolumeControl.restore() applies
-- the persisted value to the proxy at boot; it must run after audio is
-- initialized (i.e. after PlotAudio.loadAll), since the proxy's setter is
-- a no-op until ma_engine_init has run.

VolumeControl = VolumeControl or {}

local PREF_KEY = "MasterVolume"

-- Mirrors the proxy's ensure_audio default. If we change one, change both,
-- otherwise restore() at boot will silently re-set the volume to a different
-- value than the proxy chose for users who have never opened Settings.
local DEFAULT_VOLUME = 0.1

local function clampUnit(v)
    if type(v) ~= "number" then
        return DEFAULT_VOLUME
    end
    if v < 0 then
        return 0
    end
    if v > 1 then
        return 1
    end
    return v
end

function VolumeControl.get()
    if civvaccess_shared.masterVolume == nil then
        civvaccess_shared.masterVolume = clampUnit(Prefs.getFloat(PREF_KEY, DEFAULT_VOLUME))
    end
    return civvaccess_shared.masterVolume
end

function VolumeControl.set(v)
    local clamped = clampUnit(v)
    civvaccess_shared.masterVolume = clamped
    Prefs.setFloat(PREF_KEY, clamped)
    if audio ~= nil then
        audio.set_master_volume(clamped)
    end
end

-- Push the persisted value to the proxy. Call after PlotAudio.loadAll so
-- the audio engine is initialized; before that, audio.set_master_volume is
-- a no-op and our intent would be silently dropped.
function VolumeControl.restore()
    local v = VolumeControl.get()
    if audio ~= nil then
        audio.set_master_volume(v)
    end
end
