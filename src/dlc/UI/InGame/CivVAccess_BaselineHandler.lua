-- Routes the in-game cursor keys (Q/A/Z/E/D/C movement, S orient,
-- Shift+S recenter, W economy, X combat) to the Cursor module. Sits at
-- the bottom of the HandlerStack so any popup / overlay above it that
-- sets capturesAllInput will pre-empt the cursor without us having to
-- coordinate.

BaselineHandler = {}

local MOD_NONE  = 0
local MOD_SHIFT = 1

local function speak(s)
    if s == nil or s == "" then return end
    SpeechPipeline.speakInterrupt(s)
end

local function bind(key, mods, action, description)
    return { key = key, mods = mods, fn = action, description = description }
end

-- Each cursor binding wraps the cursor call so the HandlerStack table only
-- ever sees a no-arg function. Direction is hard-coded per binding because
-- there are six -- a single dispatch table would cost more than the six
-- explicit closures and lose grep-ability.
local function moveDir(dir)
    return function() speak(Cursor.move(dir)) end
end

function BaselineHandler.create()
    local h = {
        name = "Baseline",
        capturesAllInput = false,
        bindings = {
            -- Letter keys in Civ V's Keys enum are `Keys.<letter>` (no VK_
            -- prefix); only special keys use VK_ (VK_LEFT, VK_ESCAPE, etc.).
            bind(Keys.Q, MOD_NONE, moveDir(DirectionTypes.DIRECTION_NORTHWEST), "Move cursor NW"),
            bind(Keys.E, MOD_NONE, moveDir(DirectionTypes.DIRECTION_NORTHEAST), "Move cursor NE"),
            bind(Keys.A, MOD_NONE, moveDir(DirectionTypes.DIRECTION_WEST),      "Move cursor W"),
            bind(Keys.D, MOD_NONE, moveDir(DirectionTypes.DIRECTION_EAST),      "Move cursor E"),
            bind(Keys.Z, MOD_NONE, moveDir(DirectionTypes.DIRECTION_SOUTHWEST), "Move cursor SW"),
            bind(Keys.C, MOD_NONE, moveDir(DirectionTypes.DIRECTION_SOUTHEAST), "Move cursor SE"),
            bind(Keys.S, MOD_NONE,  function() speak(Cursor.orient())   end, "Orient from capital"),
            bind(Keys.S, MOD_SHIFT, function() speak(Cursor.recenter()) end, "Recenter on selected unit"),
            bind(Keys.W, MOD_NONE,  function() speak(Cursor.economy())  end, "Economy details"),
            bind(Keys.X, MOD_NONE,  function() speak(Cursor.combat())   end, "Combat details"),
        },
        helpEntries = {
            { keyLabel = "TXT_KEY_CIVVACCESS_CURSOR_HELP_KEY_MOVE",
              description = "TXT_KEY_CIVVACCESS_CURSOR_HELP_DESC_MOVE" },
            { keyLabel = "TXT_KEY_CIVVACCESS_CURSOR_HELP_KEY_ORIENT",
              description = "TXT_KEY_CIVVACCESS_CURSOR_HELP_DESC_ORIENT" },
            { keyLabel = "TXT_KEY_CIVVACCESS_CURSOR_HELP_KEY_RECENTER",
              description = "TXT_KEY_CIVVACCESS_CURSOR_HELP_DESC_RECENTER" },
            { keyLabel = "TXT_KEY_CIVVACCESS_CURSOR_HELP_KEY_ECONOMY",
              description = "TXT_KEY_CIVVACCESS_CURSOR_HELP_DESC_ECONOMY" },
            { keyLabel = "TXT_KEY_CIVVACCESS_CURSOR_HELP_KEY_COMBAT",
              description = "TXT_KEY_CIVVACCESS_CURSOR_HELP_DESC_COMBAT" },
        },
    }
    return h
end
