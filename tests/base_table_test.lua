-- BaseTable tests. Loads the production module against a synthetic data
-- model so navigation, sort, search, dedup, and lifecycle behavior can be
-- exercised without engine globals.

local T = require("support")
local M = {}

local warns, errors
local speaks
local pediaCalls

local function setup()
    warns, errors = {}, {}
    Log.warn = function(m)
        warns[#warns + 1] = m
    end
    Log.error = function(m)
        errors[#errors + 1] = m
    end
    Log.info = function() end
    Log.debug = function() end

    UI.ShiftKeyDown = function()
        return false
    end
    UI.CtrlKeyDown = function()
        return false
    end
    UI.AltKeyDown = function()
        return false
    end

    speaks = {}
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    SpeechPipeline._reset()
    SpeechPipeline._speakAction = function(text, interrupt)
        speaks[#speaks + 1] = { text = text, interrupt = interrupt }
    end
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TypeAheadSearch.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseTableCore.lua")

    pediaCalls = {}
    Events = Events or {}
    Events.SearchForPediaEntry = function(name)
        pediaCalls[#pediaCalls + 1] = name
    end

    CivVAccess_Strings = CivVAccess_Strings or {}
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TBL_TAB"] = "TestTab"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TBL_COL_NAME"] = "Name"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TBL_COL_POP"] = "Pop"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TBL_COL_GOLD"] = "Gold"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TBL_COL_FOOD"] = "Food"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_BASETABLE_SORT_DESC"] = "{1_Col}, descending"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_BASETABLE_SORT_ASC"] = "{1_Col}, ascending"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_BASETABLE_SORT_CLEARED"] = "{1_Col}, sort cleared"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_SEARCH_NO_MATCH"] = "no match for {1_Buffer}"
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_SEARCH_CLEARED"] = "search cleared"
end

-- Build a small fixed table: 3 cities x 3 columns (Name, Pop, Gold).
local function makeBasicSpec()
    local rows = {
        { name = "Rome", pop = 5, gold = 12 },
        { name = "Athens", pop = 3, gold = 20 },
        { name = "Memphis", pop = 7, gold = 7 },
    }
    return {
        tabName = "TXT_KEY_CIVVACCESS_TBL_TAB",
        columns = {
            {
                name = "TXT_KEY_CIVVACCESS_TBL_COL_NAME",
                getCell = function(r) return r.name end,
                sortKey = function(r) return r.name end,
            },
            {
                name = "TXT_KEY_CIVVACCESS_TBL_COL_POP",
                getCell = function(r) return tostring(r.pop) end,
                sortKey = function(r) return r.pop end,
            },
            {
                name = "TXT_KEY_CIVVACCESS_TBL_COL_GOLD",
                getCell = function(r) return tostring(r.gold) end,
                sortKey = function(r) return r.gold end,
            },
        },
        rebuildRows = function() return rows end,
        rowLabel = function(r) return r.name end,
    }
end

-- Factory --------------------------------------------------------------

function M.test_create_requires_tabName()
    setup()
    local spec = makeBasicSpec()
    spec.tabName = nil
    local ok = pcall(BaseTable.create, spec)
    T.falsy(ok)
end

function M.test_create_requires_columns()
    setup()
    local spec = makeBasicSpec()
    spec.columns = {}
    local ok = pcall(BaseTable.create, spec)
    T.falsy(ok)
end

function M.test_create_requires_rebuildRows_and_rowLabel()
    setup()
    local spec = makeBasicSpec()
    spec.rebuildRows = nil
    local ok = pcall(BaseTable.create, spec)
    T.falsy(ok)

    spec = makeBasicSpec()
    spec.rowLabel = nil
    ok = pcall(BaseTable.create, spec)
    T.falsy(ok)
end

function M.test_create_shape()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    T.eq(h.capturesAllInput, true)
    T.eq(type(h.bindings), "table")
    T.eq(type(h.helpEntries), "table")
    T.eq(type(h.onTabActivated), "function")
    T.eq(type(h.onTabDeactivated), "function")
    T.eq(type(h.handleSearchInput), "function")
    T.eq(type(h.onActivate), "function")
end

-- Activation -----------------------------------------------------------

function M.test_first_open_announce_false_chains_first_cell_queued()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    -- Expect speakQueued("Rome, Name, Rome") (rowLabel + colName + cell).
    T.eq(#speaks, 1)
    T.eq(speaks[1].interrupt, false, "first-open announce=false must chain (queued)")
    T.truthy(speaks[1].text:find("Rome"), "text contains row label")
    T.truthy(speaks[1].text:find("Name"), "text contains column name")
end

function M.test_first_open_announce_true_speaks_tabName_then_cell()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, true)
    T.eq(speaks[1].text, "TestTab")
    T.eq(speaks[1].interrupt, true)
    T.eq(speaks[2].interrupt, false, "cell speech chains queued after tabName interrupt")
    T.truthy(speaks[2].text:find("Rome"))
end

function M.test_reactivation_after_deactivate_preserves_cursor()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, true)
    -- Move down twice to row 3, right once to col 2.
    h.bindings[2].fn()  -- VK_DOWN
    h.bindings[2].fn()
    h.bindings[4].fn()  -- VK_RIGHT
    -- Cursor should now be row 3 (Memphis), col 2 (Pop).
    h.onTabDeactivated()
    speaks = {}
    SpeechPipeline._reset()
    h.onTabActivated(h, true)
    -- Re-activation speaks tabName + full cell. _initialized is still true,
    -- so cursor is preserved at row 3 col 2.
    T.eq(speaks[1].text, "TestTab")
    -- Look for Memphis + Pop + 7 in the second utterance.
    local text = speaks[2].text
    T.truthy(text:find("Memphis"))
    T.truthy(text:find("Pop"))
    T.truthy(text:find("7"))
end

-- Navigation -----------------------------------------------------------

local function findBinding(h, key, mods)
    mods = mods or 0
    for _, b in ipairs(h.bindings) do
        if b.key == key and (b.mods or 0) == mods then
            return b.fn
        end
    end
    return nil
end

function M.test_down_navigates_data_rows_no_wrap()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_DOWN)()
    T.eq(speaks[#speaks].text:match("^[^,]+"), "Athens", "row 2 is Athens")
    findBinding(h, Keys.VK_DOWN)()
    findBinding(h, Keys.VK_DOWN)()  -- past end; no-op
    -- Last meaningful speech is row 3 Memphis.
    T.truthy(speaks[#speaks].text:find("Memphis"))
end

function M.test_up_from_first_data_row_moves_to_header()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_UP)()
    -- _row is now 0 (header). Speech is just the column name.
    T.eq(speaks[#speaks].text, "Name")
    findBinding(h, Keys.VK_UP)()  -- already at header; no-op
end

function M.test_left_right_wrap_columns()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    -- From col 1 (Name), Left wraps to col 3 (Gold).
    findBinding(h, Keys.VK_LEFT)()
    -- Row didn't change so only column name + cell speak (dedup elides row label).
    T.truthy(speaks[#speaks].text:find("Gold"))
    -- Right wraps back to col 1 (Name).
    findBinding(h, Keys.VK_RIGHT)()
    T.truthy(speaks[#speaks].text:find("Name"))
end

function M.test_home_jumps_to_first_data_row_end_jumps_to_last()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    -- Move to last row.
    findBinding(h, Keys.VK_END)()
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_HOME)()
    T.truthy(speaks[#speaks].text:find("Rome"))
    findBinding(h, Keys.VK_END)()
    T.truthy(speaks[#speaks].text:find("Memphis"))
end

-- Smart speech dedup ---------------------------------------------------

function M.test_dedup_elides_row_label_when_only_column_changes()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_RIGHT)()
    -- Same row, different column. Speech should NOT include "Rome" again.
    local text = speaks[#speaks].text
    T.falsy(text:find("Rome"), "row label elided when only column changed")
    T.truthy(text:find("Pop"), "column name spoken")
end

function M.test_dedup_elides_column_name_when_only_row_changes()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_DOWN)()
    -- Different row, same column. Speech should NOT include "Name" again.
    local text = speaks[#speaks].text
    T.truthy(text:find("Athens"), "row label spoken")
    T.falsy(text:find("Name"), "column name elided when only row changed")
end

-- Sort -----------------------------------------------------------------

function M.test_enter_on_header_cycles_sort_descending_first()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    -- Move up to header.
    findBinding(h, Keys.VK_UP)()
    speaks = {}
    SpeechPipeline._reset()
    -- Move to col 2 (Pop) -- sortable numeric column.
    findBinding(h, Keys.VK_RIGHT)()
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_RETURN)()
    T.eq(speaks[1].text, "Pop, descending")
    -- Down to first data row -- should now be Memphis (highest pop=7).
    findBinding(h, Keys.VK_DOWN)()
    T.truthy(speaks[#speaks].text:find("Memphis"), "highest pop appears first descending")
end

function M.test_enter_on_header_cycles_through_asc_then_cleared()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    findBinding(h, Keys.VK_UP)()
    -- Sort col 1 (Name).
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_RETURN)()  -- desc
    T.eq(speaks[#speaks].text, "Name, descending")
    findBinding(h, Keys.VK_RETURN)()  -- asc
    T.eq(speaks[#speaks].text, "Name, ascending")
    findBinding(h, Keys.VK_RETURN)()  -- cleared
    T.eq(speaks[#speaks].text, "Name, sort cleared")
    -- Down to first data row -- should be Rome again (original iteration order).
    findBinding(h, Keys.VK_DOWN)()
    T.truthy(speaks[#speaks].text:find("Rome"), "natural order restored after sort cleared")
end

function M.test_enter_on_header_for_unsortable_column_is_silent()
    setup()
    local spec = makeBasicSpec()
    -- Strip sortKey from col 1 (Name).
    spec.columns[1].sortKey = nil
    local h = BaseTable.create(spec)
    h.onTabActivated(h, false)
    findBinding(h, Keys.VK_UP)()
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_RETURN)()
    T.eq(#speaks, 0, "non-sortable column is silent on Enter")
end

-- Enter on data row ---------------------------------------------------

function M.test_enter_on_data_row_invokes_column_enterAction()
    setup()
    local actioned = {}
    local spec = makeBasicSpec()
    spec.columns[1].enterAction = function(row)
        actioned[#actioned + 1] = row.name
    end
    local h = BaseTable.create(spec)
    h.onTabActivated(h, false)
    findBinding(h, Keys.VK_RETURN)()
    T.eq(#actioned, 1)
    T.eq(actioned[1], "Rome")
end

function M.test_enter_on_data_row_without_action_re_speaks_cell()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    findBinding(h, Keys.VK_RETURN)()
    -- No enterAction defined; cell re-spoken (forced).
    T.truthy(#speaks >= 1)
    T.truthy(speaks[#speaks].text:find("Rome"))
end

-- Type-ahead search ---------------------------------------------------

function M.test_search_jumps_to_matching_column()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    speaks = {}
    SpeechPipeline._reset()
    -- Press 'g' (lowercase) to search for "Gold".
    local consumed = h.handleSearchInput(h, 0x47, 0)  -- 'G'
    T.eq(consumed, true)
    -- Should have moved to col 3 (Gold) and spoken the cell.
    T.truthy(speaks[#speaks].text:find("Gold"))
end

function M.test_search_ignores_ctrl_chord()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    h.onTabActivated(h, false)
    -- Ctrl+G should NOT route to search.
    local consumed = h.handleSearchInput(h, 0x47, 2)  -- 'G' with Ctrl
    T.eq(consumed, false)
end

-- Pedia ---------------------------------------------------------------

function M.test_ctrl_i_invokes_pedia_when_column_provides_pediaName()
    setup()
    local spec = makeBasicSpec()
    spec.columns[1].pediaName = function(row) return "PEDIA_" .. row.name end
    local h = BaseTable.create(spec)
    h.onTabActivated(h, false)
    local fn = findBinding(h, Keys.I, 2)
    T.truthy(fn, "Ctrl+I binding present when any column has pediaName")
    fn()
    T.eq(#pediaCalls, 1)
    T.eq(pediaCalls[1], "PEDIA_Rome")
end

function M.test_ctrl_i_binding_absent_when_no_column_has_pediaName()
    setup()
    local h = BaseTable.create(makeBasicSpec())
    local fn = findBinding(h, Keys.I, 2)
    T.falsy(fn, "Ctrl+I binding absent when no column has pediaName")
end

-- Live re-query (no cache) --------------------------------------------

function M.test_rebuildRows_called_fresh_on_each_navigation()
    setup()
    local callCount = 0
    local spec = makeBasicSpec()
    local origRebuild = spec.rebuildRows
    spec.rebuildRows = function()
        callCount = callCount + 1
        return origRebuild()
    end
    local h = BaseTable.create(spec)
    h.onTabActivated(h, false)
    local before = callCount
    findBinding(h, Keys.VK_DOWN)()
    findBinding(h, Keys.VK_DOWN)()
    findBinding(h, Keys.VK_RIGHT)()
    T.truthy(callCount > before, "rebuildRows fires on each navigation")
end

-- Empty data ----------------------------------------------------------

function M.test_empty_table_lands_on_header_row()
    setup()
    local spec = makeBasicSpec()
    spec.rebuildRows = function() return {} end
    local h = BaseTable.create(spec)
    h.onTabActivated(h, true)
    T.eq(h._row, 0)
    -- Speech: tabName interrupt, then header column name queued.
    T.eq(speaks[1].text, "TestTab")
    T.eq(speaks[1].interrupt, true)
    T.eq(speaks[2].text, "Name")
    T.eq(speaks[2].interrupt, false)
end

return M
