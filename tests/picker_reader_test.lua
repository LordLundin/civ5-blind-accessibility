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

-- session.install-driven tests --------------------------------------------
--
-- These go through the real install path (which needs a ContextPtr) so we
-- can exercise the reader-tab nameFn + Ctrl+Up/Down hooks PickerReader
-- wires. The stub ContextPtr captures the ShowHide/Input handlers so tests
-- can drive them manually.

local function makeContextPtr()
    return {
        SetShowHideHandler = function(self, fn) self._sh = fn end,
        SetInputHandler    = function(self, fn) self._in = fn end,
        _hidden            = false,
        IsHidden           = function(self) return self._hidden end,
        SetUpdate          = function(self, fn) self._update = fn end,
    }
end

local function makeInstalledFixture()
    local session = PickerReader.create()
    local buildCalls = {}
    local defaultBuilder = function(handler, id)
        buildCalls[#buildCalls + 1] = id
        return {
            items = {
                BaseMenuItems.Text({ labelText = "first leaf " .. id }),
                BaseMenuItems.Text({ labelText = "second leaf " .. id }),
            },
            autoDrillToLevel = 1,
        }
    end
    local pickerItems = {
        session.Entry({ id = "A", labelText = "Alpha", buildReader = defaultBuilder }),
        BaseMenuItems.Group({
            labelText = "Group",
            items = {
                session.Entry({ id = "B", labelText = "Bravo",   buildReader = defaultBuilder }),
                session.Entry({ id = "C", labelText = "Charlie", buildReader = defaultBuilder }),
            },
        }),
        session.Entry({ id = "D", labelText = "Delta", buildReader = defaultBuilder }),
    }
    CivVAccess_Strings["TXT_KEY_INSTALL_PICKER_TAB"] = "Picker"
    CivVAccess_Strings["TXT_KEY_INSTALL_READER_TAB"] = "Content"
    local ctx = makeContextPtr()
    local handler = session.install(ctx, {
        name          = "InstalledPedia",
        displayName   = "Installed Pedia",
        pickerTabName = "TXT_KEY_INSTALL_PICKER_TAB",
        readerTabName = "TXT_KEY_INSTALL_READER_TAB",
        pickerItems   = pickerItems,
    })
    -- Mimic the engine's show sequence that BaseMenu.install wires: the
    -- ShowHide closure pushes the handler onto HandlerStack + fires
    -- onActivate. Without it the menu isn't active and InputRouter
    -- dispatch goes nowhere.
    ctx._sh(false, false)
    return session, handler, ctx, buildCalls
end

function M.test_install_reader_nameFn_speaks_article_title_not_content()
    setup()
    local _, handler, _, buildCalls = makeInstalledFixture()
    -- Activate Alpha (top-level entry).
    speaks = {}
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    T.eq(buildCalls[#buildCalls], "A", "build fired for Alpha")
    T.eq(handler._tabIndex, 2, "switched to reader")
    local saidAlpha, saidContent = false, false
    for _, s in ipairs(speaks) do
        if tostring(s.text):find("Alpha", 1, true)  then saidAlpha = true end
        if tostring(s.text):find("Content", 1, true) then saidContent = true end
    end
    T.truthy(saidAlpha, "article title 'Alpha' spoken on reader switch")
    T.falsy(saidContent, "static 'Content' tab name suppressed by nameFn")
end

function M.test_install_reader_nameFn_empty_when_no_selection()
    setup()
    local _, handler, _, _ = makeInstalledFixture()
    -- User Tabs into the reader before picking anything. nameFn returns
    -- empty -> no tab-name speech; the placeholder item still speaks.
    speaks = {}
    InputRouter.dispatch(Keys.VK_TAB, 0, WM_KEYDOWN)
    T.eq(handler._tabIndex, 2, "tabbed to reader")
    local saidContent = false
    for _, s in ipairs(speaks) do
        if tostring(s.text):find("Content", 1, true) then saidContent = true end
    end
    T.falsy(saidContent, "Content tab-name suppressed when no article selected")
end

function M.test_install_reader_ctrl_down_advances_article()
    setup()
    local _, handler, _, buildCalls = makeInstalledFixture()
    -- Land on Alpha so selectedId is set.
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    T.eq(buildCalls[#buildCalls], "A")
    local callsBefore = #buildCalls
    speaks = {}
    -- Ctrl+Down should advance to Bravo (next in flat order: A, B, C, D).
    InputRouter.dispatch(Keys.VK_DOWN, 2, WM_KEYDOWN)
    T.eq(buildCalls[#buildCalls], "B", "Ctrl+Down advanced to next entry")
    T.eq(#buildCalls, callsBefore + 1, "buildReader fired once for the new entry")
    local saidBravo = false
    for _, s in ipairs(speaks) do
        if tostring(s.text):find("Bravo", 1, true) then saidBravo = true; break end
    end
    T.truthy(saidBravo, "Bravo article title announced on Ctrl+Down")
end

function M.test_install_reader_ctrl_up_goes_to_previous_article()
    setup()
    local _, handler, _, buildCalls = makeInstalledFixture()
    -- Start on Charlie by drilling into group + picking second entry.
    InputRouter.dispatch(Keys.VK_DOWN,   0, WM_KEYDOWN) -- Alpha -> Group
    InputRouter.dispatch(Keys.VK_RIGHT,  0, WM_KEYDOWN) -- drill group
    InputRouter.dispatch(Keys.VK_DOWN,   0, WM_KEYDOWN) -- Bravo -> Charlie
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN) -- activate Charlie
    T.eq(buildCalls[#buildCalls], "C")
    speaks = {}
    InputRouter.dispatch(Keys.VK_UP, 2, WM_KEYDOWN) -- Ctrl+Up
    T.eq(buildCalls[#buildCalls], "B", "Ctrl+Up moved to previous entry")
end

function M.test_install_reader_ctrl_up_at_first_article_is_noop()
    setup()
    local _, _, _, buildCalls = makeInstalledFixture()
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN) -- Alpha
    local callsBefore = #buildCalls
    InputRouter.dispatch(Keys.VK_UP, 2, WM_KEYDOWN)
    T.eq(#buildCalls, callsBefore,
        "Ctrl+Up at first article does not re-fire buildReader (no wrap)")
end

function M.test_install_reader_ctrl_down_at_last_article_is_noop()
    setup()
    local _, _, _, buildCalls = makeInstalledFixture()
    -- Navigate to Delta (last entry).
    InputRouter.dispatch(Keys.VK_END,    0, WM_KEYDOWN)
    InputRouter.dispatch(Keys.VK_RETURN, 0, WM_KEYDOWN)
    T.eq(buildCalls[#buildCalls], "D")
    local callsBefore = #buildCalls
    InputRouter.dispatch(Keys.VK_DOWN, 2, WM_KEYDOWN)
    T.eq(#buildCalls, callsBefore,
        "Ctrl+Down at last article does not re-fire buildReader (no wrap)")
end

function M.test_install_reader_ctrl_keys_on_picker_tab_use_default_behavior()
    setup()
    local _, handler, _, buildCalls = makeInstalledFixture()
    -- Still on picker, selectedId is nil. Ctrl+Down at level 1 is the
    -- default "next sibling group" navigation; with a flat picker it
    -- just moves cursor, never invokes buildReader.
    T.eq(handler._tabIndex, 1, "on picker tab")
    InputRouter.dispatch(Keys.VK_DOWN, 2, WM_KEYDOWN)
    T.eq(#buildCalls, 0, "picker-tab Ctrl+Down does not trigger article nav")
end

return M
