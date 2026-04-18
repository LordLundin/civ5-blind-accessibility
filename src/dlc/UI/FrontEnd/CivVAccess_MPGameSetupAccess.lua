-- MPGameSetupScreen (Multiplayer -> Host) accessibility wiring. Same nested
-- shape as AdvancedSetup: flat leaves at the top level for each global
-- setting, plus drill-in groups for Victory Conditions, Game Options, and
-- DLC Allowed (all dynamically built by InstanceManager into per-section
-- stacks). MP has no per-slot AI panel on this screen; player slot
-- selection happens in the Staging Room after Host.
--
-- Visibility proxies handle mode-dependent hiding: the game-name /
-- private-game pair is hidden in hotseat, TurnMode is hidden in hotseat,
-- the scenario checkbox and Mods button are only visible in
-- ModMultiplayer mode, ExitButton is dedicated-server-only. The item's
-- visibilityControl gates isNavigable, so our menu silently skips over
-- hidden controls without special-casing mode in this file.

include("CivVAccess_FrontendCommon")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

-- Dynamic children --------------------------------------------------------

local function victoryChildrenFn()
    return function()
        local items = {}
        if g_VictoryCondtionsManager == nil then return items end
        for _, inst in ipairs(g_VictoryCondtionsManager.m_AllocatedInstances) do
            local cb = inst.GameOptionRoot
            local label = ""
            local ok, btn = pcall(function() return cb:GetTextButton() end)
            if ok and btn then
                local ok2, t = pcall(function() return btn:GetText() end)
                if ok2 and t then label = tostring(t) end
            end
            items[#items + 1] = BaseMenuItems.Checkbox({
                control   = cb,
                labelText = label,
            })
        end
        return items
    end
end

local function gameOptionsChildrenFn()
    return function()
        local items = {}
        if g_DropDownOptionsManager ~= nil then
            for _, inst in ipairs(g_DropDownOptionsManager.m_AllocatedInstances) do
                local label = ""
                local ok, t = pcall(function() return inst.OptionName:GetText() end)
                if ok and t then label = tostring(t) end
                items[#items + 1] = BaseMenuItems.Pulldown({
                    control   = inst.OptionDropDown,
                    labelText = label,
                })
            end
        end
        if g_GameOptionsManager ~= nil then
            for _, inst in ipairs(g_GameOptionsManager.m_AllocatedInstances) do
                local cb = inst.GameOptionRoot
                local label = ""
                local ok, btn = pcall(function() return cb:GetTextButton() end)
                if ok and btn then
                    local ok2, t = pcall(function() return btn:GetText() end)
                    if ok2 and t then label = tostring(t) end
                end
                items[#items + 1] = BaseMenuItems.Checkbox({
                    control   = cb,
                    labelText = label,
                })
            end
        end
        return items
    end
end

local function dlcChildrenFn()
    return function()
        local items = {}
        if g_DLCAllowedManager == nil then return items end
        for _, inst in ipairs(g_DLCAllowedManager.m_AllocatedInstances) do
            local cb = inst.GameOptionRoot
            local label = ""
            local ok, btn = pcall(function() return cb:GetTextButton() end)
            if ok and btn then
                local ok2, t = pcall(function() return btn:GetText() end)
                if ok2 and t then label = tostring(t) end
            end
            items[#items + 1] = BaseMenuItems.Checkbox({
                control   = cb,
                labelText = label,
            })
        end
        return items
    end
end

-- Top-level items ---------------------------------------------------------

local function buildItems(handler)
    local items = {
        -- Game name + privacy (hidden wholesale in hotseat via GameNameBox).
        BaseMenuItems.Textfield({ controlName = "NameBox",
            visibilityControlName = "GameNameBox",
            textKey = "TXT_KEY_CIVVACCESS_FIELD_GAME_NAME" }),
        BaseMenuItems.Checkbox({ controlName = "PrivateGameCheckbox",
            textKey = "TXT_KEY_MULTIPLAYER_HOST_PRIVATE_GAME",
            activateCallback = function() OnPrivateGame() end }),
        -- Global settings.
        BaseMenuItems.Pulldown({ controlName = "MapTypePullDown",
            textKey = "TXT_KEY_AD_SETUP_MAP_TYPE" }),
        BaseMenuItems.Pulldown({ controlName = "MapSizePullDown",
            textKey = "TXT_KEY_AD_SETUP_MAP_SIZE" }),
        BaseMenuItems.Pulldown({ controlName = "GameSpeedPullDown",
            textKey = "TXT_KEY_AD_SETUP_GAME_SPEED" }),
        BaseMenuItems.Pulldown({ controlName = "EraPull",
            textKey = "TXT_KEY_AD_SETUP_GAME_ERA" }),
        -- TurnMode visibility lives on the wrapper container (hidden in
        -- hotseat). Our Pulldown item doesn't take a visibility control
        -- directly, so proxy via a Choice wrapper -- except the simplest
        -- thing is to rely on Controls.TurnModePull's own Hidden state.
        -- The base sets SetHide on TurnModeRoot, not TurnModePull, so we
        -- gate with a visibilityControlName. Uses the Pulldown control
        -- field directly because we need the visibility proxy.
        BaseMenuItems.Pulldown({ controlName = "TurnModePull",
            textKey = "TXT_KEY_AD_SETUP_GAME_TURN_MODE",
            visibilityControlName = "TurnModeRoot" }),
        BaseMenuItems.Slider({ controlName = "MinorCivsSlider",
            labelControlName = "MinorCivsLabel",
            textKey = "TXT_KEY_AD_SETUP_CITY_STATES" }),
        BaseMenuItems.Checkbox({ controlName = "MaxTurnsCheck",
            textKey    = "TXT_KEY_AD_SETUP_MAX_TURNS",
            tooltipKey = "TXT_KEY_AD_SETUP_MAX_TURNS_TT",
            activateCallback = function() OnMaxTurnsChecked() end }),
        BaseMenuItems.Textfield({ controlName = "MaxTurnsEdit",
            visibilityControlName = "MaxTurnsEditbox",
            textKey       = "TXT_KEY_CIVVACCESS_FIELD_MAX_TURNS",
            priorCallback = OnMaxTurnsEditBoxChange }),
        BaseMenuItems.Checkbox({ controlName = "TurnTimerCheck",
            textKey    = "TXT_KEY_GAME_OPTION_END_TURN_TIMER_ENABLED",
            tooltipKey = "TXT_KEY_GAME_OPTION_END_TURN_TIMER_ENABLED_HELP",
            activateCallback = function() OnTurnTimerChecked() end }),
        BaseMenuItems.Textfield({ controlName = "TurnTimerEdit",
            visibilityControlName = "TurnTimerEditbox",
            textKey       = "TXT_KEY_CIVVACCESS_FIELD_TURN_TIMER",
            priorCallback = OnTurnTimerEditBoxChange }),
        -- Scenario checkbox (ModMultiplayer mode only; ScenarioCheck's
        -- wrapper box hides when not in mods mode). ModsButton is rendered
        -- by the base but has no click handler, so it's informational
        -- only -- skipped from the item list.
        BaseMenuItems.Checkbox({ controlName = "ScenarioCheck",
            visibilityControlName = "LoadScenarioBox",
            textKey          = "TXT_KEY_LOAD_SCENARIO",
            activateCallback = function() OnSenarioCheck() end }),
    }
    items[#items + 1] = BaseMenuItems.Group({
        textKey = "TXT_KEY_CIVVACCESS_GROUP_VICTORY_CONDITIONS",
        itemsFn = victoryChildrenFn(),
        cached  = false,
    })
    items[#items + 1] = BaseMenuItems.Group({
        textKey = "TXT_KEY_CIVVACCESS_GROUP_GAME_OPTIONS",
        itemsFn = gameOptionsChildrenFn(),
        cached  = false,
    })
    items[#items + 1] = BaseMenuItems.Group({
        textKey = "TXT_KEY_CIVVACCESS_GROUP_DLC_ALLOWED",
        itemsFn = dlcChildrenFn(),
        cached  = false,
    })
    -- Action row.
    items[#items + 1] = BaseMenuItems.Button({ controlName = "BackButton",
        textKey  = "TXT_KEY_BACK_BUTTON",
        activate = function() OnBack() end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "ExitButton",
        textKey  = "TXT_KEY_EXIT_BUTTON",
        activate = function() OnExitGame() end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "LoadGameButton",
        textKey    = "TXT_KEY_LOAD_GAME",
        tooltipKey = "TXT_KEY_LOAD_GAME_TT",
        activate   = function() OnLoadGame() end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "DefaultButton",
        textKey    = "TXT_KEY_AD_SETUP_DEFAULT",
        tooltipKey = "TXT_KEY_AD_SETUP_ADD_DEFAULT_TT",
        activate   = function() OnDefaultButton() end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "LaunchButton",
        textKey  = "TXT_KEY_HOST_GAME",
        activate = function() OnStart() end })
    return items
end

BaseMenu.install(ContextPtr, {
    name          = "MPGameSetup",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MP_GAME_SETUP"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    onShow        = function(h)
        h.setItems(buildItems(h))
    end,
    items         = {
        -- Placeholder; onShow rebuilds the real list before push + announce.
        BaseMenuItems.Button({ controlName = "LaunchButton",
            textKey  = "TXT_KEY_HOST_GAME",
            activate = function() end }),
    },
})
