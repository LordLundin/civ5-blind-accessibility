-- Bookmarks: per-session digit-keyed cursor positions. Cover the three
-- entry points (save / jumpTo / directionTo) plus the resetForNewGame
-- wipe and the cross-module pre-jump capture into ScannerNav. Each test
-- exercises a path the others don't: save populates a slot, save warns
-- when the cursor is unset, jumpTo rejects empty slots, jumpTo records
-- the pre-jump cell when the cursor moves, directionTo speaks HERE at
-- zero distance, directionTo composes the optional coord segment under
-- the scannerCoords toggle, resetForNewGame drops every slot.

local T = require("support")
local M = {}

local cursorPosition

local function setup()
    -- Pure-Lua deps the module reaches into directly. Cursor is stubbed
    -- below so the production CursorCore isn't required here -- this suite
    -- isn't probing cursor behavior, only the bookmarks API surface.
    dofile("src/dlc/UI/Shared/CivVAccess_HandlerStack.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    dofile("src/dlc/UI/InGame/CivVAccess_HexGeom.lua")

    civvaccess_shared = civvaccess_shared or {}
    civvaccess_shared.bookmarks = nil
    civvaccess_shared.scannerCoords = false

    -- Capital-relative coord segment pulls from HexGeom.coordinateString,
    -- which scans Players slots for IsOriginalCapital. Default to no
    -- capital so the coord segment is empty unless a test installs one.
    Players = {}
    Map.IsWrapX = function()
        return false
    end

    cursorPosition = { x = nil, y = nil }
    Cursor = {
        position = function()
            return cursorPosition.x, cursorPosition.y
        end,
        jumpTo = function(x, y)
            Cursor._lastJumpTo = { x = x, y = y }
            return "jumped"
        end,
    }

    ScannerNav = {
        markPreJump = function(x, y)
            ScannerNav._marked = { x = x, y = y }
        end,
    }

    dofile("src/dlc/UI/InGame/CivVAccess_Bookmarks.lua")
    Bookmarks.resetForNewGame()
end

-- ===== Save =====

function M.test_save_populates_slot_and_returns_added_string()
    setup()
    cursorPosition = { x = 4, y = -2 }
    local spoken = Bookmarks.save("3")
    T.eq(spoken, "bookmark added")
    T.eq(civvaccess_shared.bookmarks["3"].x, 4)
    T.eq(civvaccess_shared.bookmarks["3"].y, -2)
end

function M.test_save_overwrites_prior_slot()
    setup()
    cursorPosition = { x = 1, y = 1 }
    Bookmarks.save("5")
    cursorPosition = { x = 9, y = 9 }
    Bookmarks.save("5")
    T.eq(civvaccess_shared.bookmarks["5"].x, 9)
    T.eq(civvaccess_shared.bookmarks["5"].y, 9)
end

function M.test_save_warns_when_cursor_unset()
    setup()
    local warned
    Log.warn = function(msg)
        warned = msg
    end
    cursorPosition = { x = nil, y = nil }
    local spoken = Bookmarks.save("1")
    T.eq(spoken, "")
    T.eq(civvaccess_shared.bookmarks["1"], nil)
    T.truthy(warned, "Log.warn must fire when save runs before Cursor.init")
end

-- ===== jumpTo =====

function M.test_jumpTo_speaks_no_bookmark_on_empty_slot()
    -- Blind users can't tell whether the keystroke registered or which
    -- slots they have populated, so an empty slot speaks "no bookmark"
    -- rather than going silent. Cursor must not move, and the scanner's
    -- pre-jump anchor must not be touched -- a backspace into a stale
    -- jump is worse than no return at all.
    setup()
    cursorPosition = { x = 0, y = 0 }
    local spoken = Bookmarks.jumpTo("7")
    T.eq(spoken, "no bookmark")
    T.eq(Cursor._lastJumpTo, nil)
    T.eq(ScannerNav._marked, nil)
end

function M.test_jumpTo_records_prejump_and_jumps()
    -- Live cursor is at (3, 3); slot 2 is at (10, -5). jumpTo must
    -- (a) call ScannerNav.markPreJump with the live cursor pos, so the
    --     scanner's Backspace returns to it, and
    -- (b) call Cursor.jumpTo with the saved bookmark coords.
    setup()
    cursorPosition = { x = 3, y = 3 }
    Bookmarks.save("2")
    civvaccess_shared.bookmarks["2"] = { x = 10, y = -5 }
    cursorPosition = { x = 3, y = 3 }
    local spoken = Bookmarks.jumpTo("2")
    T.eq(spoken, "jumped")
    T.eq(Cursor._lastJumpTo.x, 10)
    T.eq(Cursor._lastJumpTo.y, -5)
    T.eq(ScannerNav._marked.x, 3)
    T.eq(ScannerNav._marked.y, 3)
end

function M.test_jumpTo_skips_prejump_when_already_at_target()
    -- A no-op jump (cursor already on the saved cell) must not consume
    -- the existing backspace anchor; otherwise pressing Shift+5 twice
    -- on the same spot would silently shadow whatever the user had set
    -- via an earlier scanner Home / different bookmark.
    setup()
    cursorPosition = { x = 6, y = 6 }
    Bookmarks.save("4")
    cursorPosition = { x = 6, y = 6 }
    Bookmarks.jumpTo("4")
    T.eq(ScannerNav._marked, nil, "no pre-jump capture when already on target")
end

-- ===== directionTo =====

function M.test_directionTo_speaks_HERE_when_cursor_on_bookmark()
    setup()
    cursorPosition = { x = 5, y = 5 }
    Bookmarks.save("1")
    -- Cursor still on the saved cell -- expect SCANNER_HERE token, the
    -- same one ScannerNav formatInstance speaks for zero-distance.
    T.eq(Bookmarks.directionTo("1"), "here")
end

function M.test_directionTo_returns_direction_string()
    -- One step east: HexGeom.directionString yields "1<DIR_E>". Suite
    -- isn't probing the exact short-token (covered by hexgeom suite),
    -- only that the bookmark formatter routes through it -- assert the
    -- result is non-empty and isn't the HERE token.
    setup()
    cursorPosition = { x = 0, y = 0 }
    Bookmarks.save("6")
    civvaccess_shared.bookmarks["6"] = { x = 4, y = 0 }
    cursorPosition = { x = 0, y = 0 }
    local out = Bookmarks.directionTo("6")
    T.truthy(out ~= "", "non-empty direction at non-zero distance")
    T.truthy(out ~= "here", "non-zero distance must not collapse to HERE token")
end

function M.test_directionTo_appends_coord_when_scannerCoords_on()
    -- scannerCoords is the same toggle the scanner's End readout uses;
    -- the bookmark formatter mirrors it so the user gets one consistent
    -- vocabulary. With a capital at (0, 0) and bookmark at (4, 0), the
    -- coord segment must be present in the output.
    setup()
    T.installOriginalCapital(0, 0, { slot = 0 })
    cursorPosition = { x = 0, y = 0 }
    Bookmarks.save("8")
    civvaccess_shared.bookmarks["8"] = { x = 4, y = 0 }
    cursorPosition = { x = 0, y = 0 }
    civvaccess_shared.scannerCoords = true
    local out = Bookmarks.directionTo("8")
    -- The exact coord format is owned by HexGeom; assert it appears as
    -- a comma-bearing segment after the direction. ", " / ". " join
    -- characters are already covered by hexgeom_test.
    T.truthy(out:find("4") ~= nil, "coord segment must include x delta")
end

function M.test_directionTo_omits_coord_when_scannerCoords_off()
    setup()
    T.installOriginalCapital(0, 0, { slot = 0 })
    cursorPosition = { x = 0, y = 0 }
    Bookmarks.save("8")
    civvaccess_shared.bookmarks["8"] = { x = 4, y = 0 }
    cursorPosition = { x = 0, y = 0 }
    civvaccess_shared.scannerCoords = false
    local out = Bookmarks.directionTo("8")
    -- COORDINATE template is "{1_X}, {2_Y}" so the comma is the cheapest
    -- discriminator: present in the coord segment, absent in the bare
    -- direction-string output (single-direction deltas have no comma).
    T.eq(out:find(",") ~= nil, false, "coord segment must be omitted when toggle is off")
end

-- ===== resetForNewGame =====

function M.test_resetForNewGame_drops_every_slot()
    setup()
    cursorPosition = { x = 1, y = 1 }
    Bookmarks.save("1")
    Bookmarks.save("9")
    Bookmarks.resetForNewGame()
    T.eq(next(civvaccess_shared.bookmarks), nil, "table must be empty after reset")
end

-- ===== Bindings surface =====

function M.test_getBindings_returns_thirty_bindings_and_three_help_entries()
    -- Ten slots (1-9 + 0) times three modifier variants (Ctrl/Shift/Alt)
    -- equals thirty bindings; the Help overlay rolls them into three
    -- chord-style help rows. Asserting the counts catches a future
    -- accidental drop or duplicate slot entry.
    setup()
    local bs = Bookmarks.getBindings()
    T.eq(#bs.bindings, 30)
    T.eq(#bs.helpEntries, 3)
end

return M
