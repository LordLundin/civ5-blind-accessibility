-- BaselineHandler now owns the in-game cursor key map. The integration of
-- those bindings (cursor movement, owner-prefix diff, etc.) is covered by
-- cursor_test; this suite asserts only handler shape and dispatch wiring
-- so a future refactor that breaks the bindings table is caught here.

local T = require("support")
local M = {}

local function setup()
    -- Stub the cursor with capturing fakes BEFORE BaselineHandler loads,
    -- so its closures bind to these. Production loads Cursor first via
    -- Boot's include order; the test mimics that explicitly.
    Cursor = {
        _calls = {},
        move     = function(d) table.insert(Cursor._calls, "move:" .. tostring(d)); return "" end,
        orient   = function()  table.insert(Cursor._calls, "orient");  return "" end,
        recenter = function()  table.insert(Cursor._calls, "recenter"); return "" end,
        economy  = function()  table.insert(Cursor._calls, "economy"); return "" end,
        combat   = function()  table.insert(Cursor._calls, "combat");  return "" end,
    }
    SpeechPipeline = SpeechPipeline or {}
    SpeechPipeline.speakInterrupt = function(_) end
    dofile("src/dlc/UI/InGame/CivVAccess_BaselineHandler.lua")
end

function M.test_create_returns_named_handler_with_help_entries()
    setup()
    local h = BaselineHandler.create()
    T.eq(h.name, "Baseline")
    T.eq(h.capturesAllInput, false)
    T.truthy(#h.bindings >= 10, "expected the cursor binding set, got " .. #h.bindings)
    T.truthy(#h.helpEntries >= 5, "expected one help entry per cursor key cluster")
end

local function findBinding(h, key, mods)
    for _, b in ipairs(h.bindings) do
        if b.key == key and (b.mods or 0) == mods then return b end
    end
end

function M.test_movement_bindings_dispatch_to_cursor_with_correct_direction()
    setup()
    local h = BaselineHandler.create()
    findBinding(h, Keys.VK_Q, 0).fn()
    findBinding(h, Keys.VK_E, 0).fn()
    T.eq(Cursor._calls[1], "move:" .. tostring(DirectionTypes.DIRECTION_NORTHWEST))
    T.eq(Cursor._calls[2], "move:" .. tostring(DirectionTypes.DIRECTION_NORTHEAST))
end

function M.test_shift_s_recenters_plain_s_orients()
    setup()
    local h = BaselineHandler.create()
    findBinding(h, Keys.VK_S, 0).fn()  -- plain
    findBinding(h, Keys.VK_S, 1).fn()  -- shift
    T.eq(Cursor._calls[1], "orient")
    T.eq(Cursor._calls[2], "recenter")
end

return M
