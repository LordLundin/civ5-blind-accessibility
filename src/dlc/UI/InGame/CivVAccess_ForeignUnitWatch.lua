-- Speaks up to four lines at the start of every player turn covering
-- foreign units that entered or walked out of the active team's view
-- during the AI turn just past. Splits hostile (at-war + barb) from
-- neutral (every foreign owner you can see who isn't at war with you,
-- civilians included). The same four strings are parked on
-- civvaccess_shared so NotificationLogPopupAccess can prepend them at
-- the top of F7 for the duration of the player's turn.
--
-- Strategy is snapshot-diff at turn boundaries. A unit walks-into-view
-- and back-out within the same AI turn nets to nothing in the diff and
-- produces no announcement, which is the desired behaviour for screen-
-- reader users (transient appearances aren't actionable). Single-
-- player only by design: simultaneous-turn multiplayer has no clean
-- turn boundary to anchor the snapshot pair to.
--
-- Destroyed units are excluded from both directions. A unit in the
-- prior snapshot but not in the current visible set is "left" only if
-- Players[i]:GetUnitByID(id) still resolves -- the unit is alive but
-- has walked into fog. If the engine no longer has the unit, it's been
-- destroyed and we drop it: "no longer in view" misframes a death, the
-- combat readout already speaks kills the active player participated
-- in, and witnessing third-party kills reliably would need a death-
-- event listener with runtime-uncertain visibility queries.
--
-- Bucket is locked at snapshot time per side. For the entered list we
-- bucket against current world state at announce time; for left we use
-- the bucket cached on the snapshot entry. A unit you last saw as
-- neutral that walks into fog after a war declaration still announces
-- as a neutral departure: we describe what you saw, not retcon the
-- bucket. The engine's own war-declared notification covers the war
-- event itself.
--
-- Game-load priming. The snapshot is module-local state and dies on
-- env reload (load-game-from-game or fresh-process load). install-
-- Listeners primes _snapshot from current visibility so the first
-- diff after a load doesn't announce every visible foreign unit as
-- freshly entered. civvaccess_shared.foreignUnitDelta gets cleared at
-- the same time so F7 doesn't show stale strings carried over from a
-- prior session via the shared table.

ForeignUnitWatch = {}

-- Snapshot entry shape:
-- { ownerId, unitId, civAdjKey, unitDescKey, bucket = "hostile" | "neutral" }
local _snapshot = {}

local function globalKey(ownerId, unitId)
    return tostring(ownerId) .. ":" .. tostring(unitId)
end

-- "hostile" / "neutral" / nil. Nil for own player, dead players, and
-- teammates -- those don't belong in either announcement bucket.
local function classifyOwner(ownerId, activePlayerId, activeTeam)
    if ownerId == activePlayerId then
        return nil
    end
    local owner = Players[ownerId]
    if owner == nil or not owner:IsAlive() then
        return nil
    end
    if owner:IsBarbarian() then
        return "hostile"
    end
    local ownerTeam = owner:GetTeam()
    if ownerTeam == activeTeam then
        return nil
    end
    if Teams[activeTeam]:IsAtWar(ownerTeam) then
        return "hostile"
    end
    return "neutral"
end

local function unitMetadata(unit, ownerId, bucket)
    local owner = Players[ownerId]
    local civAdjKey = owner and owner:GetCivilizationAdjectiveKey() or nil
    local row = GameInfo.Units[unit:GetUnitType()]
    local unitDescKey = row and row.Description or nil
    return {
        ownerId = ownerId,
        unitId = unit:GetID(),
        civAdjKey = civAdjKey,
        unitDescKey = unitDescKey,
        bucket = bucket,
    }
end

-- Walks every foreign player slot up through the barbarian index and
-- collects visible-to-active-team units into a keyed table. Visibility
-- filter mirrors ScannerBackendUnits (IsVisible AND not IsInvisible) so
-- stealth and recon-blocking behave the same here.
local function buildVisibleSet()
    local set = {}
    local activePlayerId = Game.GetActivePlayer()
    local activeTeam = Game.GetActiveTeam()
    local maxIndex = (GameDefines and GameDefines.MAX_CIV_PLAYERS) or 63
    for i = 0, maxIndex do
        if i ~= activePlayerId then
            local player = Players[i]
            if player ~= nil and player:IsAlive() then
                local bucket = classifyOwner(i, activePlayerId, activeTeam)
                if bucket ~= nil then
                    for unit in player:Units() do
                        if not unit:IsInvisible(activeTeam, false) then
                            local plot = unit:GetPlot()
                            if plot ~= nil and plot:IsVisible(activeTeam, false) then
                                local meta = unitMetadata(unit, i, bucket)
                                if meta.civAdjKey ~= nil and meta.unitDescKey ~= nil then
                                    set[globalKey(i, unit:GetID())] = meta
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return set
end

-- "3 Arabian Warrior" form, comma-joined. No plural -- Civ V's text data
-- has no TXT_KEY_UNIT_*_PLURAL keys, hand-rolling per-unit / per-locale
-- plural rules is a maintenance trap, and screen readers parse "3
-- Warrior" as plural from context.
local function formatList(entries)
    local counts = {}
    for _, e in ipairs(entries) do
        local key = e.civAdjKey .. "|" .. e.unitDescKey
        local bucket = counts[key]
        if bucket == nil then
            counts[key] = {
                count = 1,
                civ = Text.key(e.civAdjKey),
                unit = Text.key(e.unitDescKey),
            }
        else
            bucket.count = bucket.count + 1
        end
    end
    local pieces = {}
    for _, b in pairs(counts) do
        if b.count > 1 then
            pieces[#pieces + 1] = tostring(b.count) .. " " .. b.civ .. " " .. b.unit
        else
            pieces[#pieces + 1] = b.civ .. " " .. b.unit
        end
    end
    return table.concat(pieces, ", ")
end

local function formatLine(entries, txtKey)
    if #entries == 0 then
        return ""
    end
    return Text.format(txtKey, formatList(entries))
end

local function bucketByCategory(entries)
    local hostile, neutral = {}, {}
    for _, e in ipairs(entries) do
        if e.bucket == "hostile" then
            hostile[#hostile + 1] = e
        else
            neutral[#neutral + 1] = e
        end
    end
    return hostile, neutral
end

function ForeignUnitWatch._onTurnEnd()
    local ok, err = pcall(function()
        _snapshot = buildVisibleSet()
        civvaccess_shared.foreignUnitDelta = nil
    end)
    if not ok then
        Log.error("ForeignUnitWatch: TurnEnd snapshot failed: " .. tostring(err))
    end
end

function ForeignUnitWatch._onTurnStart()
    local ok, err = pcall(function()
        local current = buildVisibleSet()

        local enteredAll = {}
        for key, entry in pairs(current) do
            if _snapshot[key] == nil then
                enteredAll[#enteredAll + 1] = entry
            end
        end

        local leftAll = {}
        for key, entry in pairs(_snapshot) do
            if current[key] == nil then
                local owner = Players[entry.ownerId]
                if owner ~= nil and owner:GetUnitByID(entry.unitId) ~= nil then
                    leftAll[#leftAll + 1] = entry
                end
            end
        end

        local hE, nE = bucketByCategory(enteredAll)
        local hL, nL = bucketByCategory(leftAll)

        local lines = {
            hostileEntered = formatLine(hE, "TXT_KEY_CIVVACCESS_FOREIGN_HOSTILE_ENTERED"),
            hostileLeft    = formatLine(hL, "TXT_KEY_CIVVACCESS_FOREIGN_HOSTILE_LEFT"),
            neutralEntered = formatLine(nE, "TXT_KEY_CIVVACCESS_FOREIGN_NEUTRAL_ENTERED"),
            neutralLeft    = formatLine(nL, "TXT_KEY_CIVVACCESS_FOREIGN_NEUTRAL_LEFT"),
        }
        local anything = false
        for _, line in pairs(lines) do
            if line ~= "" then
                anything = true
                break
            end
        end
        if anything then
            civvaccess_shared.foreignUnitDelta = lines
        else
            civvaccess_shared.foreignUnitDelta = nil
        end
        -- Stable speech order: entered before left, hostile before
        -- neutral. Keeps the audible shape predictable for the user.
        local order = {
            lines.hostileEntered, lines.hostileLeft,
            lines.neutralEntered, lines.neutralLeft,
        }
        for _, line in ipairs(order) do
            if line ~= "" then
                SpeechPipeline.speakQueued(line)
            end
        end
        _snapshot = current
    end)
    if not ok then
        Log.error("ForeignUnitWatch: TurnStart diff failed: " .. tostring(err))
    end
end

-- Registers fresh listeners on every call. See CivVAccess_Boot.lua's
-- LoadScreenClose registration for the rationale: prior-Context listener
-- closures die on load-game-from-game.
function ForeignUnitWatch.installListeners()
    _snapshot = buildVisibleSet()
    civvaccess_shared.foreignUnitDelta = nil
    if Events ~= nil and Events.ActivePlayerTurnEnd ~= nil then
        Events.ActivePlayerTurnEnd.Add(ForeignUnitWatch._onTurnEnd)
    else
        Log.warn("ForeignUnitWatch: Events.ActivePlayerTurnEnd missing")
    end
    if Events ~= nil and Events.ActivePlayerTurnStart ~= nil then
        Events.ActivePlayerTurnStart.Add(ForeignUnitWatch._onTurnStart)
    else
        Log.warn("ForeignUnitWatch: Events.ActivePlayerTurnStart missing")
    end
end
