-- Cross-session user preference storage backed by Modding.OpenUserData.
-- The engine persists key/value pairs in a per-user file outside of any
-- savegame. Writes are multiplayer-safe: user data is not part of the
-- save, the mod-hash handshake, or anything enumerated in the lobby; it
-- only shapes client-side behaviour.
--
-- Engine quirks this wrapper hides:
--   * modID is an arbitrary string (unregistered modIDs are accepted).
--   * Version must be a number; passing a string throws "bad argument #2".
--   * Handle is userdata with dot-access .GetValue / .SetValue.
--   * Number values roundtrip as-is. Boolean roundtripping is unverified,
--     so setBool encodes as 0/1 and getBool decodes with "nonzero means
--     true" so a default-shaped engine coercion can't silently flip a
--     saved setting.
--
-- Version is fixed at 1 and should only bump when we want to drop all
-- existing saved values (e.g., a breaking key-layout change). Bumping
-- silently orphans every prior row.

Prefs = Prefs or {}

local MOD_ID = "40a9df7b-ae9f-48db-abb5-44afe0420524"
local MOD_VERSION = 1

local _handle = nil
local _openAttempted = false

local function handle()
    if _handle ~= nil then
        return _handle
    end
    if _openAttempted then
        return nil
    end
    _openAttempted = true
    if Modding == nil or Modding.OpenUserData == nil then
        Log.info("Prefs: Modding.OpenUserData unavailable; defaults will apply")
        return nil
    end
    local ok, h = pcall(Modding.OpenUserData, MOD_ID, MOD_VERSION)
    if not ok then
        Log.error("Prefs: OpenUserData threw: " .. tostring(h))
        return nil
    end
    if h == nil then
        Log.warn("Prefs: OpenUserData returned nil")
        return nil
    end
    _handle = h
    Log.info("Prefs: OpenUserData handle acquired")
    return _handle
end

function Prefs.getBool(key, default)
    local h = handle()
    if h == nil then
        return default
    end
    local ok, v = pcall(function()
        return h.GetValue(key)
    end)
    if not ok then
        Log.error("Prefs.getBool(" .. tostring(key) .. ") threw: " .. tostring(v))
        return default
    end
    if v == nil then
        return default
    end
    return v ~= 0
end

function Prefs.setBool(key, v)
    local h = handle()
    if h == nil then
        return
    end
    local encoded = v and 1 or 0
    local ok, err = pcall(function()
        h.SetValue(key, encoded)
    end)
    if not ok then
        Log.error("Prefs.setBool(" .. tostring(key) .. ") threw: " .. tostring(err))
    end
end
