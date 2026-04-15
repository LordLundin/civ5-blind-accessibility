-- TextFilter tests. Exercises every branch of markup stripping, icon
-- substitution, whitespace normalization, and control-char handling.
-- Each case asserts one invariant; overlaps are intentional for the
-- composed-markup rows where interactions can break unrelated branches.

local T = require("support")

-- Stub Log before loading the filter; the filter warns about unknown icons
-- through Log.debug. Capture warnings so we can assert them.
local capturedLogs = {}
Log = {
    debug = function(msg) capturedLogs[#capturedLogs + 1] = msg end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
}

dofile("src/mod/UI/CivVAccess_TextFilter.lua")

local function resetIconState()
    -- Re-load to clear _iconMap and _warnedIcons closure state.
    capturedLogs = {}
    dofile("src/mod/UI/CivVAccess_TextFilter.lua")
end

-- nil / empty / type coercion -----------------------------------------------

T.case("nil input returns empty string", function()
    T.eq(TextFilter.filter(nil), "")
end)

T.case("empty string returns empty string", function()
    T.eq(TextFilter.filter(""), "")
end)

T.case("number input coerced via tostring", function()
    T.eq(TextFilter.filter(42), "42")
end)

-- Fast-path passthrough -----------------------------------------------------

T.case("plain text passes through unchanged", function()
    T.eq(TextFilter.filter("Next Turn"), "Next Turn")
end)

T.case("fast path collapses internal whitespace", function()
    T.eq(TextFilter.filter("a   b\tc"), "a b c")
end)

T.case("fast path trims leading and trailing whitespace", function()
    T.eq(TextFilter.filter("  hello  "), "hello")
end)

-- Bracket tokens ------------------------------------------------------------

T.case("NEWLINE becomes a single space", function()
    T.eq(TextFilter.filter("line1[NEWLINE]line2"), "line1 line2")
end)

T.case("COLOR_* tokens stripped", function()
    T.eq(TextFilter.filter("[COLOR_POSITIVE_TEXT]+3[ENDCOLOR] food"),
        "+3 food")
end)

T.case("COLOR token with digits stripped", function()
    T.eq(TextFilter.filter("[COLOR_PLAYER_GOLD_TEXT_1]gold[ENDCOLOR]"), "gold")
end)

T.case("STYLE token stripped by catchall", function()
    T.eq(TextFilter.filter("[STYLE_HEADER]Title"), "Title")
end)

T.case("TAB token stripped", function()
    T.eq(TextFilter.filter("a[TAB]b"), "ab")
end)

T.case("BULLET token stripped", function()
    T.eq(TextFilter.filter("[BULLET]item"), "item")
end)

T.case("numeric bracket token stripped", function()
    T.eq(TextFilter.filter("[X123]after"), "after")
end)

T.case("lowercase bracket content is not stripped", function()
    -- Catchall requires uppercase/digits only; [foo] should pass through.
    T.eq(TextFilter.filter("keep [foo] this"), "keep [foo] this")
end)

-- Icon substitution ---------------------------------------------------------

T.case("registered icon substituted with spoken form", function()
    resetIconState()
    TextFilter.registerIcon("ICON_GOLD", "gold")
    T.eq(TextFilter.filter("costs [ICON_GOLD]"), "costs gold")
end)

T.case("unregistered icon is stripped", function()
    resetIconState()
    T.eq(TextFilter.filter("costs [ICON_MYSTERY]"), "costs")
end)

T.case("unregistered icon warns once then silently", function()
    resetIconState()
    TextFilter.filter("[ICON_MYSTERY]")
    TextFilter.filter("[ICON_MYSTERY] again")
    local hits = 0
    for _, msg in ipairs(capturedLogs) do
        if msg:find("ICON_MYSTERY") then hits = hits + 1 end
    end
    T.eq(hits, 1, "warning should fire exactly once per icon name")
end)

T.case("different unregistered icons each warn once", function()
    resetIconState()
    TextFilter.filter("[ICON_A][ICON_B]")
    T.eq(#capturedLogs, 2)
end)

T.case("registered icon wins over catchall bracket strip", function()
    resetIconState()
    TextFilter.registerIcon("ICON_FOOD", "food")
    T.eq(TextFilter.filter("[ICON_FOOD][COLOR_X]+2[ENDCOLOR]"), "food+2")
end)

-- Control characters -------------------------------------------------------

T.case("control chars stripped", function()
    T.eq(TextFilter.filter("a\1b\8c\31d"), "abcd")
end)

T.case("newline and tab preserved (as whitespace, then collapsed)", function()
    T.eq(TextFilter.filter("a\nb\tc"), "a b c")
end)

T.case("null byte stripped", function()
    T.eq(TextFilter.filter("a\0b"), "ab")
end)

-- Emdash -------------------------------------------------------------------

T.case("emdash replaced with space", function()
    T.eq(TextFilter.filter("Rome\226\128\148a city"), "Rome a city")
end)

T.case("emdash surrounded by spaces collapses to one space", function()
    T.eq(TextFilter.filter("Rome \226\128\148 a city"), "Rome a city")
end)

-- Artifacts ----------------------------------------------------------------

T.case("colon-period artifact collapses to period", function()
    -- Left by tag removal: "Yield:[ICON_FOOD]." with unknown icon -> "Yield:."
    resetIconState()
    T.eq(TextFilter.filter("Yield:[ICON_UNKNOWN]."), "Yield.")
end)

-- Composed markup ----------------------------------------------------------

T.case("composed: color, newline, icon, whitespace", function()
    resetIconState()
    TextFilter.registerIcon("ICON_GOLD", "gold")
    T.eq(
        TextFilter.filter("[COLOR_X]  [ICON_GOLD]\t+5[ENDCOLOR][NEWLINE]next"),
        "gold +5 next")
end)

T.case("composed: all markup with emdash and control chars", function()
    resetIconState()
    TextFilter.registerIcon("ICON_PROD", "production")
    T.eq(
        TextFilter.filter("\1[STYLE_H][ICON_PROD]\226\128\148city[NEWLINE]"),
        "production city")
end)

os.exit(T.run() and 0 or 1)
