-- PickerReader cross-tab behavior. Focused on the two-tab activate/restore
-- contract so regressions in BaseMenu's switchTab / cycleTab don't silently
-- break the pedia flow. BaseMenu + BaseMenuItems + TypeAheadSearch are
-- loaded for real; engine globals come from Polyfill.

local T = require("support")
local M = {}

local warns, errors
local speaks

local WM_KEYDOWN = 256

local function setup()
    warns, errors = {}, {}
    Log.warn  = function(m) warns[#warns + 1]  = m end
    Log.error = function(m) errors[#errors + 1] = m end
    Log.info  = function() end
    Log.debug = function() end

    UI.ShiftKeyDown = function() return false end
    UI.CtrlKeyDown  = function() return false end
    UI.AltKeyDown   = function() return false end
    Events.AudioPlay2DSound = function() end

    speaks = {}
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    SpeechPipeline._reset()
    SpeechPipeline._speakAction = function(text, interrupt)
        speaks[#speaks + 1] = { text = text, interrupt = interrupt }
    end
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_HandlerStack.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_InputRouter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TickPump.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_Nav.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_PullDownProbe.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuItems.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TypeAheadSearch.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuHelp.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuCore.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuEditMode.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_PickerReader.lua")

    HandlerStack._reset()
    TickPump._reset()
    Controls = {}

    CivVAccess_Strings = CivVAccess_Strings or {}
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_BUTTON_DISABLED"]   = "disabled"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_SEARCH_CLEARED"]    = "cleared"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_CHOICE_SELECTED"]   = "selected"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_PICKER_READER_EMPTY"]        = "empty"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_PICKER_READER_NO_SELECTION"] = "no selection"
    CivVAccess_Strings["TXT_KEY_PICKER_TAB"]  = "Picker"
    CivVAccess_Strings["TXT_KEY_READER_TAB"]  = "Reader"
    CivVAccess_Strings["TXT_KEY_SECTION_A"]   = "Section A"
    CivVAccess_Strings["TXT_KEY_SECTION_B"]   = "Section B"
    CivVAccess_Strings["TXT_KEY_ENTRY_ONE"]   = "Entry One"
    CivVAccess_Strings["TXT_KEY_ENTRY_TWO"]   = "Entry Two"
    CivVAccess_Strings["TXT_KEY_CAT_ONE"]     = "Cat One"
end

-- Build a simple picker tree: one category group with two entries.
local function makeFixture(buildReaderFn)
    local session = PickerReader.create()
    local buildCalls = {}
    local defaultBuilder = function(handler, id)
        buildCalls[#buildCalls + 1] = id
        return {
            items = {
                BaseMenuItems.Group({
                    labelText = "Section A for " .. id,
                    items = {
                        BaseMenuItems.Text({ labelText = "body 1 " .. id }),
                        BaseMenuItems.Text({ labelText = "body 2 " .. id }),
                    },
                }),
                BaseMenuItems.Group({
                    labelText = "Section B for " .. id,
                    items = {
                        BaseMenuItems.Text({ labelText = "body 3 " .. id }),
                    },
                }),
            },
            autoDrillToLevel = 2,
        }
    end
    local pickerItems = {
        BaseMenuItems.Group({
            labelText = "Cat One",
            items = {
                session.Entry({
                    id = "E1",
                    labelText = "Entry One",
                    buildReader = buildReaderFn or defaultBuilder,
                }),
                session.Entry({
                    id = "E2",
                    labelText = "Entry Two",
                    buildReader = buildReaderFn or defaultBuilder,
                }),
            },
        }),
    }
    return session, pickerItems, buildCalls
end

-- Bypass ContextPtr / install by building a BaseMenu directly from the
-- session's spec construction path. session.install calls BaseMenu.install
-- which needs a ContextPtr; we factor around it by replicating the bmSpec
-- building inline (the create-layer is what these tests care about).
-- Using BaseMenu.create against the two-tab spec the session would build:
local function buildHandler(session, pickerItems)
    local handler = BaseMenu.create({
        name        = "TestPedia",
        displayName = "Test Pedia",
        tabs = {
            {
                name  = "TXT_KEY_PICKER_TAB",
                items = pickerItems,
                onActivate = function(h)
                    -- Copy the session's restorePickerCursor behavior by
                    -- reading state via session.Entry closure... Not
                    -- directly accessible; rely on session.install path
                    -- instead for that case. These tests build the handler
                    -- directly to avoid ContextPtr dependence and cover
                    -- the Entry-activation contract end-to-end.
                end,
            },
            {
                name  = "TXT_KEY_READER_TAB",
                items = { BaseMenuItems.Text({ labelText = "no selection" }) },
            },
        },
    })
    HandlerStack.push(handler)
    return handler
end

-- Assertions helpers -----------------------------------------------------

local function lastSpeak() return speaks[#speaks] end

local function textsSpoken()
    local out = {}
    for _, s in ipairs(speaks) do out[#out + 1] = s.text end
    return out
end

-- Tests ------------------------------------------------------------------

function M.test_handler_starts_on_picker_tab_level_1()
    setup()
    local session, pickerItems = makeFixture()
    local h = buildHandler(session, pickerItems)
    T.eq(h._tabIndex, 1, "starts on picker tab")
    T.eq(h._level, 1, "starts at level 1")
end

function M.test_entry_activation_swaps_reader_items_and_switches_tab()
    setup()
    local session, pickerItems, buildCalls = makeFixture()
    local h = buildHandler(session, pickerItems)

    -- Drill into the category Group.
    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    T.eq(h._level, 2, "drilled into Cat One")

    -- Activate Entry One.
    speaks = {}
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)

    T.eq(buildCalls[#buildCalls], "E1", "buildReader called with entry id")
    T.eq(h._tabIndex, 2, "switched to reader tab after activation")
    -- autoDrillToLevel = 2 drills from section Group into its first body.
    T.eq(h._level, 2, "reader auto-drilled into first section")
end

function M.test_entry_activation_reading_first_body_line()
    setup()
    local session, pickerItems = makeFixture()
    local h = buildHandler(session, pickerItems)

    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    speaks = {}
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)

    -- First announcement after tab switch: tab name, then first body line.
    local texts = textsSpoken()
    local sawBody = false
    for _, t in ipairs(texts) do
        if tostring(t):find("body 1", 1, true) then sawBody = true; break end
    end
    T.truthy(sawBody, "first body line announced after reader auto-drill")
end

function M.test_same_entry_reactivated_rebuilds_reader()
    setup()
    local session, pickerItems, buildCalls = makeFixture()
    local h = buildHandler(session, pickerItems)
    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    local firstCalls = #buildCalls
    -- Tab back to picker.
    InputRouter.dispatch(Keys.VK_TAB, 1, WM_KEYDOWN) -- Shift+Tab
    T.eq(h._tabIndex, 1, "back to picker")
    -- Without the PickerReader.install restore path (buildHandler bypasses
    -- install), cursor lands on Cat One; drill back in and re-activate E1.
    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    T.eq(#buildCalls, firstCalls + 1, "buildReader re-fired (no stale cache)")
    T.eq(buildCalls[#buildCalls], "E1", "buildReader called with same id")
end

function M.test_switch_to_reader_tab_programmatically_re_announces()
    setup()
    local session, pickerItems = makeFixture()
    local h = buildHandler(session, pickerItems)

    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    -- Now on reader. Call switchToTab(2) again.
    speaks = {}
    h.switchToTab(2)
    T.truthy(#speaks > 0, "programmatic same-tab switch still announces")
end

function M.test_empty_build_result_keeps_user_on_picker()
    setup()
    local session, pickerItems = makeFixture(function(h, id)
        return { items = {}, autoDrillToLevel = 1 }
    end)
    local h = buildHandler(session, pickerItems)

    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    speaks = {}
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)

    T.eq(h._tabIndex, 1, "empty build stays on picker")
    local sawEmpty = false
    for _, s in ipairs(speaks) do
        if tostring(s.text):find("empty", 1, true) then sawEmpty = true; break end
    end
    T.truthy(sawEmpty, "empty-reader announcement spoken")
end

function M.test_autoDrill_level_one_skips_drill()
    setup()
    local session, pickerItems = makeFixture(function()
        return {
            items = {
                BaseMenuItems.Text({ labelText = "flat line one" }),
                BaseMenuItems.Text({ labelText = "flat line two" }),
            },
            autoDrillToLevel = 1,
        }
    end)
    local h = buildHandler(session, pickerItems)

    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)

    T.eq(h._tabIndex, 2, "switched to reader")
    T.eq(h._level, 1, "flat reader stays at level 1")
end

function M.test_tab_cycling_preserves_reader_items_after_selection()
    setup()
    local session, pickerItems, buildCalls = makeFixture()
    local h = buildHandler(session, pickerItems)

    InputRouter.dispatch(Keys.VK_RIGHT, 0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    local calls = #buildCalls
    -- Shift+Tab -> picker
    InputRouter.dispatch(Keys.VK_TAB, 1, WM_KEYDOWN)
    -- Tab -> reader
    InputRouter.dispatch(Keys.VK_TAB, 0, WM_KEYDOWN)

    -- Plain Tab cycling shouldn't re-invoke buildReader (only Entry activation does).
    T.eq(#buildCalls, calls, "buildReader not called on Tab cycling")
    T.eq(h._tabIndex, 2, "back on reader tab")
end

return M
