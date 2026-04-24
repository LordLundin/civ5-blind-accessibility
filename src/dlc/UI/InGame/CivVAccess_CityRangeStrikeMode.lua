-- City-ranged-strike target picker. Pushed above Baseline / Scanner after
-- the city screen closes and the engine enters INTERFACEMODE_CITY_RANGE_ATTACK.
-- Structurally a sibling to UnitTargetMode: free Q/E/A/D/Z/C cursor movement
-- via Baseline (no mapScope -- the cursor roams the whole map and Baseline's
-- per-tile speech reads what's there), Space speaks a strike-specific preview
-- ("out of range" or target identity), Enter commits, Esc cancels. Alt+QAZEDC
-- is swallowed to block Baseline's direct-move while the engine holds an
-- attack interface mode.
--
-- CanRangeStrikeNow gates the hub item, so at least one valid target exists
-- on entry. Cursor is jumped to a nearby valid target as a starting point;
-- from there the user navigates freely and Space tells them whether each
-- plot is strikeable. The commit-time CanRangeStrikeAt check is the
-- authoritative validity gate; a stray Enter on an invalid plot speaks
-- "cannot strike" and stays in the mode.
--
-- Exit (commit OR cancel OR external pop) drops back to the world map;
-- the city screen does NOT re-open. Matches the sighted banner-click
-- flow: bombarding from a banner leaves you on the world, not in the
-- city screen.

CityRangeStrikeMode = {}

local MOD_NONE = 0
local MOD_ALT = 4

local bind = HandlerStack.bind

local function speakInterrupt(text)
    if text == nil or text == "" then
        return
    end
    SpeechPipeline.speakInterrupt(text)
end

local function resolveCity(ownerID, cityID)
    local owner = Players[ownerID]
    if owner == nil then
        return nil
    end
    return owner:GetCityByID(cityID)
end

-- First non-invisible enemy unit at plot (plot defender priority). Mirrors
-- UnitTargetMode.firstEnemyUnit. Used for the Space preview fallback when
-- the plot has no enemy city.
local function topEnemyUnitAt(plot)
    if plot == nil then
        return nil
    end
    local team = Game.GetActiveTeam()
    local activePlayer = Game.GetActivePlayer()
    local isDebug = Game.IsDebugMode()
    for i = 0, plot:GetNumUnits() - 1 do
        local u = plot:GetUnit(i)
        if u ~= nil and not u:IsInvisible(team, isDebug) and u:GetOwner() ~= activePlayer then
            return u
        end
    end
    return nil
end

-- Space-preview announcement. Distinguishes three cases the user can land
-- on while roaming the map:
--   1. Plot the city CAN strike -- speak target identity (city or unit).
--   2. Plot the city cannot strike (out of range, no visible enemy, etc.) --
--      speak "cannot strike" so the user knows Enter would be rejected.
--   3. Plot the city can strike but with no surfaceable target -- speak
--      "cannot strike" too (rare; visible-enemy gate keeps these out of
--      CanRangeStrikeAt's true cases).
-- The engine exposes no Lua-side city-to-target damage function, so the
-- preview is target identity only -- the user decides from HP and
-- strength whether to commit.
local function targetAnnouncement(city, plot, x, y)
    if plot == nil then
        return ""
    end
    if not city:CanRangeStrikeAt(x, y, true, true) then
        return Text.key("TXT_KEY_CIVVACCESS_CITY_RANGED_CANNOT_STRIKE")
    end
    local targetCity = plot:GetPlotCity()
    local activePlayer = Game.GetActivePlayer()
    if targetCity ~= nil and targetCity:GetOwner() ~= activePlayer then
        return CitySpeech.identity(targetCity)
    end
    local unit = topEnemyUnitAt(plot)
    if unit ~= nil then
        return UnitSpeech.info(unit)
    end
    return Text.key("TXT_KEY_CIVVACCESS_CITY_RANGED_CANNOT_STRIKE")
end

-- Initial landing target: first plot inside the city's max strike range
-- (3 hexes covers policy-bumped cities; CanRangeStrikeAt filters the rest).
-- Iterates by expanding ring so the first match is spatially close to the
-- city rather than whatever the iteration order would otherwise pick.
-- Convenience-only -- nil result is fine, the cursor just stays where the
-- user was and they can roam to find a target on their own.
local function findFirstTarget(city)
    local cx, cy = city:GetX(), city:GetY()
    for r = 1, 3 do
        for dx = -r, r do
            for dy = -r, r do
                local plot = Map.PlotXYWithRangeCheck(cx, cy, dx, dy, r)
                if plot ~= nil then
                    local px, py = plot:GetX(), plot:GetY()
                    if city:CanRangeStrikeAt(px, py, true, true) then
                        return plot
                    end
                end
            end
        end
    end
    return nil
end

-- Abandon-entry path. Called on any bail before the handler is on the
-- stack (nil city, CanRangeStrikeNow flipped false between hub activate
-- and the deferred enter(), HandlerStack.push returning false). The
-- caller has already put the engine into CITY_RANGE_ATTACK with a
-- selected city, so every bail has to unwind that state or the user is
-- stranded in an attack mode with no binding.
local function abandonEntry()
    UI.ClearSelectedCities()
    UI.SetInterfaceMode(InterfaceModeTypes.INTERFACEMODE_SELECTION)
end

function CityRangeStrikeMode.enter(city)
    if city == nil then
        Log.warn("CityRangeStrikeMode.enter: nil city; aborting")
        abandonEntry()
        return
    end
    if not city:CanRangeStrikeNow() then
        Log.warn("CityRangeStrikeMode.enter: CanRangeStrikeNow false; aborting")
        abandonEntry()
        return
    end
    local ownerID = city:GetOwner()
    local cityID = city:GetID()

    -- Convenience landing: jump cursor to a nearby valid target on entry
    -- so the user starts on something they can fire at. CanRangeStrikeNow
    -- guarantees at least one target exists; findFirstTarget may still
    -- miss it if the city's range exceeds our 3-hex search box (modded
    -- ranges, etc.), in which case the cursor stays put and the user
    -- navigates manually.
    local initialTarget = findFirstTarget(city)

    local self = {
        name = "CityRangeStrike",
        capturesAllInput = false,
    }

    local function popHandler()
        HandlerStack.removeByName("CityRangeStrike", false)
    end

    local function commitStrike()
        local c = resolveCity(ownerID, cityID)
        if c == nil then
            popHandler()
            return
        end
        local cx, cy = Cursor.position()
        if cx == nil then
            popHandler()
            return
        end
        if not c:CanRangeStrikeAt(cx, cy, true, true) then
            speakInterrupt(Text.key("TXT_KEY_CIVVACCESS_CITY_RANGED_CANNOT_STRIKE"))
            return
        end
        -- Engine uses GAMEMESSAGE_DO_TASK / TASK_RANGED_ATTACK against the
        -- currently selected-cities list (see WorldView.lua:519). The
        -- activation flow selected the city before entering this mode,
        -- so the task targets the right attacker.
        Game.SelectedCitiesGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_TASK, TaskTypes.TASK_RANGED_ATTACK, cx, cy)
        speakInterrupt(Text.key("TXT_KEY_CIVVACCESS_CITY_RANGED_FIRED"))
        popHandler()
    end

    local noop = function() end
    self.bindings = {
        bind(Keys.VK_SPACE, MOD_NONE, function()
            local c = resolveCity(ownerID, cityID)
            if c == nil then
                return
            end
            local cx, cy = Cursor.position()
            if cx == nil then
                return
            end
            speakInterrupt(targetAnnouncement(c, Map.GetPlot(cx, cy), cx, cy))
        end, "Target preview"),
        bind(Keys.VK_RETURN, MOD_NONE, commitStrike, "Commit strike"),
        bind(Keys.VK_ESCAPE, MOD_NONE, function()
            popHandler()
            speakInterrupt(Text.key("TXT_KEY_CIVVACCESS_CANCELED"))
        end, "Cancel"),
        -- Alt+QAZEDC no-ops: Baseline binds these to direct-move, which
        -- would move a unit while the engine holds CITY_RANGE_ATTACK
        -- interface mode. Match UnitTargetMode's block pattern.
        bind(Keys.Q, MOD_ALT, noop, "Block direct-move NW"),
        bind(Keys.E, MOD_ALT, noop, "Block direct-move NE"),
        bind(Keys.A, MOD_ALT, noop, "Block direct-move W"),
        bind(Keys.D, MOD_ALT, noop, "Block direct-move E"),
        bind(Keys.Z, MOD_ALT, noop, "Block direct-move SW"),
        bind(Keys.C, MOD_ALT, noop, "Block direct-move SE"),
    }
    -- Movement help is provided by Baseline's cursor entry; we don't
    -- duplicate it here. Listing only the strike-specific keys.
    self.helpEntries = {
        {
            keyLabel = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_KEY_PREVIEW",
            description = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_DESC_PREVIEW",
        },
        {
            keyLabel = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_KEY_COMMIT",
            description = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_DESC_COMMIT",
        },
        {
            keyLabel = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_KEY_CANCEL",
            description = "TXT_KEY_CIVVACCESS_CITY_RANGED_HELP_DESC_CANCEL",
        },
    }

    self.onActivate = function()
        speakInterrupt(Text.key("TXT_KEY_CIVVACCESS_CITY_RANGED_MODE"))
        if initialTarget ~= nil then
            local tileSpeech = Cursor.jumpTo(initialTarget:GetX(), initialTarget:GetY())
            if tileSpeech ~= nil and tileSpeech ~= "" then
                SpeechPipeline.speakQueued(tileSpeech)
            end
        end
    end

    self.onDeactivate = function()
        UI.ClearSelectedCities()
        -- Return to SELECTION so the engine exits CITY_RANGE_ATTACK. Esc,
        -- commit, and any external pop all land here.
        UI.SetInterfaceMode(InterfaceModeTypes.INTERFACEMODE_SELECTION)
    end

    local pushed = HandlerStack.push(self)
    if not pushed then
        abandonEntry()
    end
end
