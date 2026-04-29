-- Text.formatPlural: bundle resolution, form selection, scalar fallback,
-- and the missing-form fallback chain. The plural rule itself is
-- exercised by plural_rules_test; this suite checks the wiring between
-- the strings table and PluralRules.

local T = require("support")
local M = {}

local warnings
local origWarn

local function setup()
    warnings = {}
    origWarn = Log.warn
    Log.warn = function(msg)
        warnings[#warnings + 1] = msg
    end
    -- Re-load Text.lua so its captured Log.warn upvalue points at the
    -- capturing stub above. The other Text wrapper tests do this too.
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")
    PluralRules._setLocale("en_US")
    CivVAccess_Strings = CivVAccess_Strings or {}
end

local function teardown(keys)
    Log.warn = origWarn
    for _, k in ipairs(keys or {}) do
        CivVAccess_Strings[k] = nil
    end
    PluralRules._setLocale("en_US")
end

function M.test_bundle_one_form_returns_singular_for_count_one()
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_TILES"] = {
        one = "{1_N} tile unexplored",
        other = "{1_N} tiles unexplored",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_TILES", 1, 1)
    T.eq(out, "1 tile unexplored")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_TILES" })
end

function M.test_bundle_other_form_returns_plural_for_count_two()
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_TILES"] = {
        one = "{1_N} tile unexplored",
        other = "{1_N} tiles unexplored",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_TILES", 5, 5)
    T.eq(out, "5 tiles unexplored")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_TILES" })
end

function M.test_count_separate_from_substitution_args()
    -- BUILDING-style template: count drives plural selection, but the
    -- substitution args are (what, turns). The caller passes `turns`
    -- twice -- once for selection, once as the {2_Turns} fill.
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_BUILDING"] = {
        one = "{1_What} {2_Turns} turn",
        other = "{1_What} {2_Turns} turns",
    }
    local out1 = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_BUILDING", 1, "Farm", 1)
    T.eq(out1, "Farm 1 turn")
    local out5 = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_BUILDING", 5, "Farm", 5)
    T.eq(out5, "Farm 5 turns")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_BUILDING" })
end

function M.test_russian_few_picks_few_form()
    setup()
    PluralRules._setLocale("ru_RU")
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_RU"] = {
        one = "{1_N} штука",
        few = "{1_N} штуки",
        many = "{1_N} штук",
        other = "{1_N} штуки",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_RU", 3, 3)
    T.eq(out, "3 штуки")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_RU" })
end

function M.test_russian_many_picks_many_form()
    setup()
    PluralRules._setLocale("ru_RU")
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_RU"] = {
        one = "{1_N} штука",
        few = "{1_N} штуки",
        many = "{1_N} штук",
        other = "{1_N} штуки",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_RU", 5, 5)
    T.eq(out, "5 штук")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_RU" })
end

function M.test_missing_form_falls_back_to_other()
    -- Bundle authored with only one + other. Russian's "few" rule
    -- selects "few", which is missing -- fallback chain takes us to
    -- "other".
    setup()
    PluralRules._setLocale("ru_RU")
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_PARTIAL"] = {
        one = "{1_N} item",
        other = "{1_N} items",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_PARTIAL", 3, 3)
    T.eq(out, "3 items")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_PARTIAL" })
end

function M.test_missing_other_falls_back_to_one()
    -- Pathological bundle that only authored "one". The fallback chain
    -- still produces something speakable rather than the raw key.
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_PATHOLOGICAL"] = {
        one = "lone form",
    }
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_PATHOLOGICAL", 5)
    T.eq(out, "lone form")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_PATHOLOGICAL" })
end

function M.test_scalar_entry_falls_through_to_format()
    -- Pre-migration scalar value -- formatPlural should still produce
    -- a substituted string by routing through Text.format. The count
    -- arg is dropped; the caller is responsible for passing it again
    -- in `...` if the template needs it.
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_SCALAR"] = "{1_N} thing"
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_SCALAR", 5, 5)
    T.eq(out, "5 thing")
    teardown({ "TXT_KEY_CIVVACCESS_TEST_SCALAR" })
end

function M.test_empty_bundle_warns_and_returns_key()
    setup()
    CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEST_EMPTY"] = {}
    local out = Text.formatPlural("TXT_KEY_CIVVACCESS_TEST_EMPTY", 1, 1)
    T.eq(out, "TXT_KEY_CIVVACCESS_TEST_EMPTY")
    T.eq(#warnings, 1)
    T.truthy(warnings[1]:find("no forms", 1, true), "warning should mention missing forms: " .. warnings[1])
    teardown({ "TXT_KEY_CIVVACCESS_TEST_EMPTY" })
end

return M
