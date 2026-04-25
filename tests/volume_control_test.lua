-- VolumeControl tests. Exercises the get / set / restore pipeline end-to-end:
-- the cache on civvaccess_shared, the Prefs writes, and the audio proxy
-- side effect. Prefs is monkey-patched to a fake handle so reads / writes
-- round-trip without needing the engine's user-data file.

local T = require("support")
local M = {}

local prefsStore

local function setup()
    Log.warn = function() end
    Log.error = function() end
    Log.info = function() end
    Log.debug = function() end

    civvaccess_shared = {}
    audio._reset()

    -- Replace Prefs.getFloat / setFloat with a capturing pair backed by a
    -- table. The real Prefs module self-degrades to defaults when Modding
    -- is absent, which would hide bugs in our setter (no roundtrip).
    prefsStore = {}
    Prefs.getFloat = function(key, default)
        local v = prefsStore[key]
        if v == nil then
            return default
        end
        return v
    end
    Prefs.setFloat = function(key, v)
        prefsStore[key] = v
    end

    dofile("src/dlc/UI/Shared/CivVAccess_VolumeControl.lua")
end

function M.test_get_returns_proxy_default_on_first_read()
    setup()
    -- 0.1 matches the proxy's ensure_audio default; getting before any
    -- set / restore must agree so the user-perceived volume stays in sync.
    T.eq(VolumeControl.get(), 0.1)
end

function M.test_get_caches_on_shared_after_first_read()
    setup()
    VolumeControl.get()
    T.eq(civvaccess_shared.masterVolume, 0.1, "first get hydrates the cache")
end

function M.test_get_reads_persisted_value()
    setup()
    prefsStore["MasterVolume"] = 0.42
    T.eq(VolumeControl.get(), 0.42)
end

function M.test_set_persists_to_prefs()
    setup()
    VolumeControl.set(0.3)
    T.eq(prefsStore["MasterVolume"], 0.3)
end

function M.test_set_updates_cache()
    setup()
    VolumeControl.set(0.7)
    T.eq(civvaccess_shared.masterVolume, 0.7)
end

function M.test_set_pushes_to_audio_proxy()
    setup()
    VolumeControl.set(0.55)
    local last = audio._calls[#audio._calls]
    T.eq(last.op, "set_master_volume")
    T.eq(last.v, 0.55)
end

function M.test_set_clamps_above_one()
    setup()
    VolumeControl.set(1.5)
    T.eq(VolumeControl.get(), 1)
    T.eq(prefsStore["MasterVolume"], 1)
end

function M.test_set_clamps_below_zero()
    setup()
    VolumeControl.set(-0.4)
    T.eq(VolumeControl.get(), 0)
    T.eq(prefsStore["MasterVolume"], 0)
end

function M.test_restore_pushes_persisted_value_to_proxy()
    setup()
    prefsStore["MasterVolume"] = 0.2
    VolumeControl.restore()
    local last = audio._calls[#audio._calls]
    T.eq(last.op, "set_master_volume")
    T.eq(last.v, 0.2)
end

return M
