-- F2 Economic Overview wrapper tests. Exercises the helpers exposed via
-- the EconomicOverviewAccess module table after dofiling the wrapper with a
-- stubbed engine surface. The TabbedShell.install at the bottom of the
-- wrapper is guarded on a real ContextPtr so dofile doesn't try to wire up
-- a fake Context.

local T = require("support")
local M = {}

local function setup()
    -- Capturing log so missing TXT_KEYs don't blow up.
    Log.warn = function() end
    Log.error = function() end
    Log.info = function() end
    Log.debug = function() end

    -- Reset speech / handler state so dofile-time writes don't leak.
    dofile("src/dlc/UI/Shared/CivVAccess_TextFilter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_SpeechPipeline.lua")
    SpeechPipeline._reset()
    dofile("src/dlc/UI/Shared/CivVAccess_Text.lua")

    Locale.ToNumber = function(n, _fmt)
        return tostring(n)
    end

    -- Engine globals the helpers reach for.
    GameOptionTypes = {
        GAMEOPTION_NO_SCIENCE = 1,
        GAMEOPTION_NO_RELIGION = 2,
        GAMEOPTION_NO_HAPPINESS = 3,
    }
    ButtonPopupTypes = ButtonPopupTypes or {}
    ButtonPopupTypes.BUTTONPOPUP_CHOOSEPRODUCTION = 100

    Game = Game or {}
    Game.IsOption = function()
        return false
    end
    Game.GetActivePlayer = function()
        return 0
    end
    Game.GetResourceUsageType = function()
        return 0
    end

    ResourceUsageTypes = ResourceUsageTypes or { RESOURCEUSAGE_BONUS = 0 }

    Players = {}
    Events = Events or {}
    Events.SerialEventGameMessagePopup = function() end

    UI = UI or {}
    UI.LookAt = function() end
    UI.SelectCity = function() end

    -- include() in the wrapper resolves to a noop here; the deps the wrapper
    -- needs (HandlerStack, BaseMenu, BaseTable, TabbedShell) are dofiled by
    -- this setup before the wrapper itself, in the order BaseMenu.install
    -- requires.
    include = function() end

    dofile("src/dlc/UI/Shared/CivVAccess_HandlerStack.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_InputRouter.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TickPump.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_Nav.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuItems.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TypeAheadSearch.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuHelp.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuTabs.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuCore.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseMenuInstall.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_TabbedShell.lua")
    dofile("src/dlc/UI/Shared/CivVAccess_BaseTableCore.lua")

    -- Make sure the install guard skips: ContextPtr is not a table-with-methods.
    ContextPtr = nil

    -- Wrapper. dofile triggers the install guard, which short-circuits.
    EconomicOverviewAccess = nil
    dofile("src/dlc/UI/InGame/Popups/CivVAccess_EconomicOverviewAccess.lua")
end

-- Stub city with the engine methods the helpers reach for. Pass `opts` to
-- override individual fields.
local function stubCity(opts)
    opts = opts or {}
    local c = {}
    function c:GetName()
        return opts.name or "Rome"
    end
    function c:GetID()
        return opts.id or 1
    end
    function c:GetPopulation()
        return opts.pop or 5
    end
    function c:GetStrengthValue()
        return opts.strength or 1500
    end
    function c:FoodDifference()
        return opts.food or 3
    end
    function c:GetYieldRate(yieldType)
        return (opts.yields or {})[yieldType] or 0
    end
    function c:GetYieldRateTimes100(yieldType)
        return ((opts.yields or {})[yieldType] or 0) * 100
    end
    function c:GetJONSCulturePerTurn()
        return opts.culture or 2
    end
    function c:GetFaithPerTurn()
        return opts.faith or 0
    end
    function c:GetProductionModifier()
        return opts.prodMod or 0
    end
    function c:GetProductionNameKey()
        return opts.prodName or "TXT_KEY_UNIT_WARRIOR"
    end
    function c:IsProduction()
        return opts.isProduction ~= false
    end
    function c:IsProductionProcess()
        return opts.isProcess or false
    end
    function c:GetCurrentProductionDifferenceTimes100()
        return opts.prodDiff or 100
    end
    function c:GetProductionTurnsLeft()
        return opts.prodTurns or 5
    end
    function c:IsCapital()
        return opts.capital or false
    end
    function c:IsPuppet()
        return opts.puppet or false
    end
    function c:IsOccupied()
        return opts.occupied or false
    end
    function c:IsNoOccupiedUnhappiness()
        return opts.noOccupiedUnhappiness or false
    end
    function c:Plot()
        return opts.plot or {}
    end
    return c
end

-- formatSigned --------------------------------------------------------

function M.test_formatSigned_positive_gets_plus()
    setup()
    T.eq(EconomicOverviewAccess.formatSigned(5), "+5")
end

function M.test_formatSigned_zero_unsigned()
    setup()
    T.eq(EconomicOverviewAccess.formatSigned(0), "0")
end

function M.test_formatSigned_negative_unsigned_native_minus()
    setup()
    T.eq(EconomicOverviewAccess.formatSigned(-3), "-3")
end

-- cityAnnotation ------------------------------------------------------

function M.test_cityAnnotation_capital()
    setup()
    local c = stubCity({ capital = true })
    T.eq(EconomicOverviewAccess.cityAnnotation(c), "capital")
end

function M.test_cityAnnotation_puppet()
    setup()
    local c = stubCity({ puppet = true })
    T.eq(EconomicOverviewAccess.cityAnnotation(c), "puppet")
end

function M.test_cityAnnotation_occupied_with_unhappiness()
    setup()
    local c = stubCity({ occupied = true, noOccupiedUnhappiness = false })
    T.eq(EconomicOverviewAccess.cityAnnotation(c), "occupied")
end

function M.test_cityAnnotation_occupied_but_no_unhappiness_unannotated()
    setup()
    local c = stubCity({ occupied = true, noOccupiedUnhappiness = true })
    T.eq(EconomicOverviewAccess.cityAnnotation(c), nil)
end

function M.test_cityAnnotation_normal_city_unannotated()
    setup()
    local c = stubCity({})
    T.eq(EconomicOverviewAccess.cityAnnotation(c), nil)
end

function M.test_cityAnnotation_capital_takes_precedence_over_puppet()
    setup()
    -- Engine guarantees a city is at most one of these, but if the helpers
    -- ever encountered both flags, capital is the more important to surface.
    local c = stubCity({ capital = true, puppet = true })
    T.eq(EconomicOverviewAccess.cityAnnotation(c), "capital")
end

-- cityRowLabel --------------------------------------------------------

function M.test_cityRowLabel_no_annotation_returns_bare_name()
    setup()
    local c = stubCity({ name = "Athens" })
    T.eq(EconomicOverviewAccess.cityRowLabel(c), "Athens")
end

function M.test_cityRowLabel_capital_appended()
    setup()
    local c = stubCity({ name = "Rome", capital = true })
    T.eq(EconomicOverviewAccess.cityRowLabel(c), "Rome (capital)")
end

function M.test_cityRowLabel_occupied_appended()
    setup()
    local c = stubCity({ name = "Sparta", occupied = true })
    T.eq(EconomicOverviewAccess.cityRowLabel(c), "Sparta (occupied)")
end

-- cityProductionPerTurn -----------------------------------------------

function M.test_cityProductionPerTurn_no_modifier()
    setup()
    local c = stubCity({ yields = { [YieldTypes.YIELD_PRODUCTION] = 12 } })
    T.eq(EconomicOverviewAccess.cityProductionPerTurn(c), 12)
end

function M.test_cityProductionPerTurn_applies_percent_modifier()
    setup()
    local c = stubCity({
        yields = { [YieldTypes.YIELD_PRODUCTION] = 10 },
        prodMod = 50,
    })
    T.eq(EconomicOverviewAccess.cityProductionPerTurn(c), 15)
end

-- buildCityColumns visibility ----------------------------------------

local function hasColumn(cols, name)
    for _, c in ipairs(cols) do
        if c.name == name then
            return true
        end
    end
    return false
end

function M.test_buildCityColumns_default_includes_science_and_faith()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    T.truthy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_SCIENCE"))
    T.truthy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_FAITH"))
end

function M.test_buildCityColumns_no_science_drops_science_column()
    setup()
    Game.IsOption = function(opt)
        return opt == GameOptionTypes.GAMEOPTION_NO_SCIENCE
    end
    local cols = EconomicOverviewAccess.buildCityColumns()
    T.falsy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_SCIENCE"))
    T.truthy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_FAITH"))
end

function M.test_buildCityColumns_no_religion_drops_faith_column()
    setup()
    Game.IsOption = function(opt)
        return opt == GameOptionTypes.GAMEOPTION_NO_RELIGION
    end
    local cols = EconomicOverviewAccess.buildCityColumns()
    T.truthy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_SCIENCE"))
    T.falsy(hasColumn(cols, "TXT_KEY_CIVVACCESS_EO_COL_FAITH"))
end

function M.test_buildCityColumns_all_have_getCell_and_sortKey()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    for _, c in ipairs(cols) do
        T.eq(type(c.getCell), "function", "column " .. c.name .. " getCell")
        T.eq(type(c.sortKey), "function", "column " .. c.name .. " sortKey")
    end
end

function M.test_buildCityColumns_name_column_has_enterAction()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    for _, c in ipairs(cols) do
        if c.name == "TXT_KEY_PRODPANEL_CITY_NAME" then
            T.eq(type(c.enterAction), "function")
            return
        end
    end
    T.truthy(false, "name column not found")
end

function M.test_buildCityColumns_production_column_has_enterAction()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    for _, c in ipairs(cols) do
        if c.name == "TXT_KEY_CIVVACCESS_EO_COL_PRODUCTION" then
            T.eq(type(c.enterAction), "function")
            return
        end
    end
    T.truthy(false, "production column not found")
end

-- Column getCell results ----------------------------------------------

function M.test_food_column_getCell_signs_positive_yield()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    local food
    for _, c in ipairs(cols) do
        if c.name == "TXT_KEY_CIVVACCESS_EO_COL_FOOD" then
            food = c
            break
        end
    end
    T.truthy(food)
    local city = stubCity({ food = 4 })
    T.eq(food.getCell(city), "+4")
end

function M.test_strength_column_getCell_divides_by_100()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    local strength
    for _, c in ipairs(cols) do
        if c.name == "TXT_KEY_CIVVACCESS_EO_COL_STRENGTH" then
            strength = c
            break
        end
    end
    T.truthy(strength)
    local city = stubCity({ strength = 1750 })
    T.eq(strength.getCell(city), "17")
end

function M.test_population_column_getCell_returns_count_string()
    setup()
    local cols = EconomicOverviewAccess.buildCityColumns()
    local pop
    for _, c in ipairs(cols) do
        if c.name == "TXT_KEY_CIVVACCESS_EO_COL_POPULATION" then
            pop = c
            break
        end
    end
    T.truthy(pop)
    local city = stubCity({ pop = 7 })
    T.eq(pop.getCell(city), "7")
end

-- productionColumnCell -------------------------------------------------

function M.test_productionColumnCell_with_active_build_includes_turns_and_name()
    setup()
    local city = stubCity({
        yields = { [YieldTypes.YIELD_PRODUCTION] = 10 },
        prodMod = 0,
        prodName = "Warrior", -- passed through Locale.ConvertTextKey
        isProduction = true,
        isProcess = false,
        prodDiff = 100,
        prodTurns = 4,
    })
    local out = EconomicOverviewAccess.productionColumnCell(city)
    T.truthy(out:find("10"), "yield in output")
    T.truthy(out:find("4 turns"), "turn count in output")
    T.truthy(out:find("Warrior"), "build name in output")
end

function M.test_productionColumnCell_with_no_production_says_none()
    setup()
    local city = stubCity({
        yields = { [YieldTypes.YIELD_PRODUCTION] = 0 },
        prodName = "",
        isProduction = false,
    })
    local out = EconomicOverviewAccess.productionColumnCell(city)
    T.truthy(out:find("no production"))
end

return M
