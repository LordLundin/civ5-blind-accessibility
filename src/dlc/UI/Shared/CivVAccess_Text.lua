-- Wrapper around Locale.ConvertTextKey that surfaces missing keys to the log.
-- A missing key in raw Locale silently returns the input string and the user
-- hears "TXT KEY FOO" spelled out. Routing through here turns that into an
-- actionable Log.warn while still returning something speakable.

Text = {}

-- Engine-style {N_Tag} substitution for mod-authored mapped strings. The
-- game's Locale.ConvertTextKey does this for TXT_KEY_*, but we short-circuit
-- Locale for our own keys to keep the mapping table as the source of truth,
-- so we do substitution here. Only the positional {N_...} form is handled;
-- the Tag after the underscore is ignored (same as the engine when args
-- arrive by position).
local function substitute(s, args, argCount)
    if argCount == 0 then
        return s
    end
    return (
        s:gsub("{(%d+)_[^}]*}", function(n)
            local v = args[tonumber(n)]
            if v == nil then
                return ""
            end
            return tostring(v)
        end)
    )
end

local function lookup(key, ...)
    if type(key) == "string" and key:sub(1, 19) == "TXT_KEY_CIVVACCESS_" then
        local mapped = CivVAccess_Strings and CivVAccess_Strings[key]
        if mapped ~= nil then
            local argCount = select("#", ...)
            if argCount == 0 then
                return mapped
            end
            return substitute(mapped, { ... }, argCount)
        end
        -- Fall through to Locale so the missing-key warning still fires via
        -- the engine's passthrough behavior (returns the key unchanged).
    end
    if select("#", ...) > 0 then
        return Locale.ConvertTextKey(key, ...)
    end
    return Locale.ConvertTextKey(key)
end

local function isTxtKey(s)
    return type(s) == "string" and s:sub(1, 8) == "TXT_KEY_"
end

function Text.key(keyName)
    local out = lookup(keyName)
    if out == keyName and isTxtKey(keyName) then
        Log.warn("Text: missing TXT_KEY " .. tostring(keyName))
    end
    return out
end

-- Like Text.key but returns nil instead of the raw key string when the lookup
-- misses. Use this when the caller has somewhere to drop the value (a part
-- list, a tooltip with a fallback) so an unresolved key never reaches Tolk
-- and gets spelled out letter by letter. Base-game data is the main source
-- of misses: a few TXT_KEY_* references point at strings that were never
-- registered (e.g. TXT_KEY_PROCESS_RESEARCH_STRATEGY).
function Text.keyOrNil(keyName)
    local out = lookup(keyName)
    if out == keyName and isTxtKey(keyName) then
        Log.warn("Text: missing TXT_KEY " .. tostring(keyName))
        return nil
    end
    return out
end

function Text.format(keyName, ...)
    local out = lookup(keyName, ...)
    if out == keyName and isTxtKey(keyName) then
        Log.warn("Text: missing TXT_KEY " .. tostring(keyName))
    end
    return out
end
