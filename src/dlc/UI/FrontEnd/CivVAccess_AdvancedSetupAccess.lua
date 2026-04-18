-- AdvancedSetup (Single Player -> Set Up Game -> Advanced) accessibility
-- wiring. First screen to use nested menus: AI player slots, Victory
-- Conditions, and Game Options are groups (Right / Enter drills in,
-- Left / Esc returns). Static leaves sit next to them at the top level.
--
-- The base file's dynamic data (AI slot rows, victory / game-option
-- checkboxes, map-script dropdowns) is built through InstanceManager so
-- there are no stable Controls.X names to wire by spec; instead we read
-- the live widgets via each slot's g_SlotInstances[i] entry and via
-- g_VictoryCondtionsManager.m_AllocatedInstances /
-- g_GameOptionsManager.m_AllocatedInstances /
-- g_DropDownOptionsManager.m_AllocatedInstances. Dynamic groups pass
-- cached=false so they rebuild on every drill (PartialSync from pulldown
-- selections can reshape the game-option set without notice).

include("CivVAccess_FrontendCommon")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

-- Max turns edit: the base-game callback is an inline anonymous fn we
-- can't capture, so duplicate the same setter. On sub pop the
-- RegisterCallback restore re-installs the engine's original.
local function maxTurnsEditCallback()
    PreGame.SetMaxTurns(Controls.MaxTurnsEdit:GetText())
end

-- Read a pulldown's current text via its button. Returns "" on failure.
local function pulldownText(control)
    if control == nil then return "" end
    local ok, btn = pcall(function() return control:GetButton() end)
    if not ok or btn == nil then return "" end
    local ok2, t = pcall(function() return btn:GetText() end)
    if not ok2 or t == nil then return "" end
    return tostring(t)
end

-- Label composition -------------------------------------------------------

local function slotLabelFn(slotIndex)
    return function()
        local slot = g_SlotInstances and g_SlotInstances[slotIndex]
        if slot == nil then return "" end
        local civText  = pulldownText(slot.CivPulldown)
        local teamText = pulldownText(slot.TeamPullDown)
        return Text.format("TXT_KEY_CIVVACCESS_AI_SLOT",
            slotIndex + 1, civText, teamText)
    end
end

-- Dynamic children --------------------------------------------------------

local function slotChildrenFn(handler, slotIndex)
    return function()
        local slot = g_SlotInstances and g_SlotInstances[slotIndex]
        if slot == nil then return {} end
        local items = {
            BaseMenuItems.Pulldown({ control = slot.CivPulldown,
                textKey = "TXT_KEY_RANDOM_LEADER" }),
            BaseMenuItems.Pulldown({ control = slot.TeamPullDown,
                textKey = "TXT_KEY_MULTIPLAYER_SELECT_TEAM" }),
        }
        -- Base file hides RemoveButton for slot 1 (games require >= 2
        -- players). Skip it from the item list too so navigation doesn't
        -- announce a permanently-disabled entry.
        if slotIndex ~= 1 then
            items[#items + 1] = BaseMenuItems.Button({
                control   = slot.RemoveButton,
                textKey   = "TXT_KEY_MODDING_DELETEMOD",
                activate  = function()
                    if PreGame.GetSlotStatus(slotIndex) == SlotStatus.SS_COMPUTER then
                        PreGame.SetSlotStatus(slotIndex, SlotStatus.SS_CLOSED)
                    end
                    PerformPartialSync()
                    handler._rebuild()
                end,
            })
        end
        return items
    end
end

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

-- Top-level items builder -------------------------------------------------

local function aiSlotGroups(handler)
    local groups = {}
    -- AdvancedSetup uses slot index 0 for the human and 1..MAX-1 for AI.
    for i = 1, GameDefines.MAX_MAJOR_CIVS - 1 do
        local slot = g_SlotInstances and g_SlotInstances[i]
        if slot ~= nil then
            groups[#groups + 1] = BaseMenuItems.Group({
                labelFn           = slotLabelFn(i),
                itemsFn           = slotChildrenFn(handler, i),
                cached            = false,
                visibilityControl = slot.Root,
            })
        end
    end
    return groups
end

local function buildItems(handler)
    local items = {
        -- Human player (inline; not a group because the player setting up
        -- the game interacts with this slot most and shouldn't need to
        -- drill). CivPulldown and CivName are mutually exclusive: the base
        -- file hides CivPulldown and shows CivName when the human has a
        -- custom leader / civ name set via Edit. Both are listed so the
        -- visible-at-runtime one is announced.
        BaseMenuItems.Pulldown({ controlName = "CivPulldown",
            textKey = "TXT_KEY_RANDOM_LEADER",
            tooltipKey = "TXT_KEY_RANDOM_LEADER_HELP" }),
        BaseMenuItems.Choice({
            visibilityControlName = "CivName",
            labelFn  = function() return Controls.CivName:GetText() or "" end,
            activate = function() UIManager:PushModal(Controls.SetCivNames) end }),
        BaseMenuItems.Pulldown({ controlName = "TeamPullDown",
            textKey = "TXT_KEY_MULTIPLAYER_SELECT_TEAM" }),
        BaseMenuItems.Button({ controlName = "EditButton",
            textKey    = "TXT_KEY_EDIT_BUTTON",
            tooltipKey = "TXT_KEY_NAME_CIV_TITLE",
            activate   = function() UIManager:PushModal(Controls.SetCivNames) end }),
        BaseMenuItems.Button({ controlName = "RemoveButton",
            textKey  = "TXT_KEY_CANCEL_BUTTON",
            activate = function() OnCancelEditPlayerDetails() end }),
        -- Global settings.
        BaseMenuItems.Pulldown({ controlName = "MapTypePullDown",
            textKey = "TXT_KEY_AD_SETUP_MAP_TYPE" }),
        BaseMenuItems.Pulldown({ controlName = "MapSizePullDown",
            textKey = "TXT_KEY_AD_SETUP_MAP_SIZE" }),
        BaseMenuItems.Pulldown({ controlName = "HandicapPullDown",
            textKey = "TXT_KEY_AD_SETUP_HANDICAP" }),
        BaseMenuItems.Pulldown({ controlName = "GameSpeedPullDown",
            textKey = "TXT_KEY_AD_SETUP_GAME_SPEED" }),
        BaseMenuItems.Pulldown({ controlName = "EraPullDown",
            textKey = "TXT_KEY_AD_SETUP_GAME_ERA" }),
        BaseMenuItems.Slider({ controlName = "MinorCivsSlider",
            labelControlName = "MinorCivsLabel",
            textKey = "TXT_KEY_AD_SETUP_CITY_STATES" }),
        BaseMenuItems.Checkbox({ controlName = "MaxTurnsCheck",
            textKey    = "TXT_KEY_AD_SETUP_MAX_TURNS",
            tooltipKey = "TXT_KEY_AD_SETUP_MAX_TURNS_TT" }),
        -- MaxTurnsEditbox wraps the EditBox; SetHide is called on the
        -- wrapper when MaxTurnsCheck toggles, so point visibility at the
        -- wrapper rather than the EditBox itself.
        BaseMenuItems.Textfield({ controlName = "MaxTurnsEdit",
            visibilityControlName = "MaxTurnsEditbox",
            textKey       = "TXT_KEY_CIVVACCESS_FIELD_MAX_TURNS",
            priorCallback = maxTurnsEditCallback }),
    }
    -- AI slot groups. Each is hidden when its Root is hidden (random
    -- world size collapses all slots under UnknownPlayers).
    for _, g in ipairs(aiSlotGroups(handler)) do
        items[#items + 1] = g
    end
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
    -- Action row.
    items[#items + 1] = BaseMenuItems.Button({ controlName = "AddAIButton",
        textKey    = "TXT_KEY_AD_SETUP_ADD_AI_PLAYER",
        tooltipKey = "TXT_KEY_AD_SETUP_ADD_AI_PLAYER_TT",
        activate   = function()
            OnAdAIClicked()
            handler._rebuild()
        end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "DefaultButton",
        textKey    = "TXT_KEY_AD_SETUP_DEFAULT",
        tooltipKey = "TXT_KEY_AD_SETUP_ADD_DEFAULT_TT",
        activate   = function()
            OnDefaultsClicked()
            handler._rebuild()
        end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "BackButton",
        textKey    = "TXT_KEY_BACK_BUTTON",
        tooltipKey = "TXT_KEY_REFRESH_GAME_LIST_TT",
        activate   = function() OnBackClicked() end })
    items[#items + 1] = BaseMenuItems.Button({ controlName = "StartButton",
        textKey  = "TXT_KEY_START_GAME",
        activate = function() OnStartClicked() end })
    return items
end

-- Rebuild the top-level item list and re-announce what the cursor lands
-- on. Called from show + from activate callbacks that reshape the slot
-- set (Add AI / Remove / Defaults). setItems already resets level to 1
-- and clamps the cursor.
local function rebuildItems(handler)
    handler.setItems(buildItems(handler))
    local items = handler._items or {}
    local idx   = handler._indices and handler._indices[1] or 1
    local item  = items[idx]
    if item ~= nil then
        SpeechPipeline.speakInterrupt(item:announce(handler))
    end
end

BaseMenu.install(ContextPtr, {
    name          = "AdvancedSetup",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_ADVANCED_SETUP"),
    preamble      = function()
        if PreGame.IsRandomWorldSize() then
            return Text.key("TXT_KEY_CIVVACCESS_UNKNOWN_PLAYERS_STATUS")
        end
        return nil
    end,
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    onShow        = function(h)
        h._rebuild = function() rebuildItems(h) end
        h.setItems(buildItems(h))
    end,
    items         = {
        -- Initial items: re-populated by onShow before the first announce.
        -- The install flow calls onShow before push, so this is a
        -- placeholder navigation list used only if g_SlotInstances is nil
        -- (Context instantiated but base file hasn't run yet). Keep it
        -- minimally valid so create's assertions pass.
        BaseMenuItems.Button({ controlName = "StartButton",
            textKey = "TXT_KEY_START_GAME",
            activate = function() end }),
    },
})
