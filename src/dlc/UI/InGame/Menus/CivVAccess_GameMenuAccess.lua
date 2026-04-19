-- GameMenu accessibility wiring. Three-tab BaseMenu:
--   Actions tab: Resume / QuickSave / Save / Load / Options / Restart /
--     Retire / Main Menu / Exit. Each Button reuses the same Controls.X the
--     base OnShowHide hides per multiplayer / scenario / tutorial / mod
--     flags, so our isNavigable / isActivatable propagate the engine's
--     visibility and disabled state without re-deriving them.
--   Details tab: synthesized Text items re-queried at announce time from
--     PreGame / GameInfo (leader, civ, era, map script, world size,
--     handicap, speed, each enabled victory, each enabled GameOption).
--     Mirrors what PopulateGameData / PopulateGameOptions feed the visual
--     panel; labelFn runs fresh on every navigate so hotseat hand-offs
--     between active players show the new player's handicap.
--   Mods tab: one Text item per Modding.GetActivatedMods() entry, sorted
--     and built on tab entry. Activated mods are fixed for the session.
-- Each tab's showPanel swaps the base screen's visual panels so a sighted
-- observer's view matches the active tab.
--
-- ExitConfirm yes/no is an overlay inside this Context (not a separate
-- LuaContext). The Main Menu item pushes a modal sub-handler with
-- capturesAllInput; bindings fire OnYes / OnNo, and a tick watches
-- ExitConfirm visibility so externally-driven dismissal pops us too.

include("CivVAccess_Polyfill")
include("CivVAccess_Log")
include("CivVAccess_TextFilter")
include("CivVAccess_InGameStrings_en_US")
include("CivVAccess_Text")
include("CivVAccess_Icons")
include("CivVAccess_SpeechEngine")
include("CivVAccess_SpeechPipeline")
include("CivVAccess_HandlerStack")
include("CivVAccess_InputRouter")
include("CivVAccess_TickPump")
include("CivVAccess_Nav")
include("CivVAccess_BaseMenuItems")
include("CivVAccess_TypeAheadSearch")
include("CivVAccess_BaseMenuHelp")
include("CivVAccess_BaseMenuTabs")
include("CivVAccess_BaseMenuCore")
include("CivVAccess_BaseMenuInstall")
include("CivVAccess_BaseMenuEditMode")
include("CivVAccess_Help")

local priorShowHide = OnShowHide
local priorInput    = InputHandler

local ACTIONS_TAB = 1
local DETAILS_TAB = 2
local MODS_TAB    = 3

-- Panel visibility ------------------------------------------------------

-- The base game toggles MainContainer vs DetailsPanel vs ModsPanel through
-- OnGameDetails / OnGameMods, but those are toggles rather than setters.
-- We drive absolute state per tab so tab switches always land on the
-- correct panel for a sighted observer.
local function showMainContainer()
    if Controls.DetailsPanel  then Controls.DetailsPanel:SetHide(true) end
    if Controls.ModsPanel     then Controls.ModsPanel:SetHide(true) end
    if Controls.MainContainer then Controls.MainContainer:SetHide(false) end
end

local function showDetailsPanel()
    if Controls.ModsPanel     then Controls.ModsPanel:SetHide(true) end
    if Controls.MainContainer then Controls.MainContainer:SetHide(true) end
    if Controls.DetailsPanel  then Controls.DetailsPanel:SetHide(false) end
end

local function showModsPanel()
    if Controls.DetailsPanel  then Controls.DetailsPanel:SetHide(true) end
    if Controls.MainContainer then Controls.MainContainer:SetHide(true) end
    if Controls.ModsPanel     then Controls.ModsPanel:SetHide(false) end
end

-- ExitConfirm modal ----------------------------------------------------

local function makeExitConfirmHandler()
    local function closeSub()
        HandlerStack.removeByName("GameMenuExitConfirm", true)
    end
    local function pressYes()
        if type(OnYes) == "function" then
            local ok, err = pcall(OnYes)
            if not ok then
                Log.error("GameMenuAccess: OnYes failed: " .. tostring(err))
            end
        end
        closeSub()
    end
    local function pressNo()
        if type(OnNo) == "function" then
            local ok, err = pcall(OnNo)
            if not ok then
                Log.error("GameMenuAccess: OnNo failed: " .. tostring(err))
            end
        end
        closeSub()
    end
    return {
        name             = "GameMenuExitConfirm",
        capturesAllInput = true,
        bindings = {
            { key = Keys.Y,         mods = 0, description = "Confirm",
              fn  = pressYes },
            { key = Keys.VK_RETURN, mods = 0, description = "Confirm",
              fn  = pressYes },
            { key = Keys.N,         mods = 0, description = "Cancel",
              fn  = pressNo },
            { key = Keys.VK_ESCAPE, mods = 0, description = "Cancel",
              fn  = pressNo },
        },
        helpEntries = {},
        onActivate = function(self)
            local text
            if Controls.Message ~= nil then
                local ok, t = pcall(function() return Controls.Message:GetText() end)
                if ok and t ~= nil and t ~= "" then text = t end
            end
            if text == nil then
                text = Locale.ConvertTextKey("TXT_KEY_MENU_RETURN_MM_WARN")
            end
            SpeechPipeline.speakInterrupt(text)
        end,
        -- Covers externally-driven dismissal: OnYes hides ExitConfirm before
        -- firing ExitToMainMenu, and the ShowHide for the transition will
        -- unwind our parent handler anyway -- but if any other path closes
        -- the confirm (base code we haven't traced, debug hot-reload),
        -- the tick keeps the stack coherent.
        tick = function(self)
            if Controls.ExitConfirm == nil then return end
            if Controls.ExitConfirm:IsHidden() then closeSub() end
        end,
    }
end

-- Actions tab ----------------------------------------------------------

local function mainMenuActivate()
    if type(OnMainMenu) == "function" then
        local ok, err = pcall(OnMainMenu)
        if not ok then
            Log.error("GameMenuAccess: OnMainMenu failed: " .. tostring(err))
            return
        end
    end
    HandlerStack.push(makeExitConfirmHandler())
end

local function buildActionsItems()
    return {
        BaseMenuItems.Button({ controlName = "ReturnButton",
            textKey  = "TXT_KEY_MENU_RETURN_TO_GAME",
            activate = function() OnReturn() end }),
        BaseMenuItems.Button({ controlName = "QuickSaveButton",
            textKey  = "TXT_KEY_MENU_QUICK_SAVE_BUTTON",
            activate = function() OnQuickSave() end }),
        BaseMenuItems.Button({ controlName = "SaveGameButton",
            textKey  = "TXT_KEY_MENU_SAVE_BUTTON",
            activate = function() OnSave() end }),
        BaseMenuItems.Button({ controlName = "LoadGameButton",
            textKey  = "TXT_KEY_MENU_LOAD_GAME_BUTTON",
            activate = function() OnLoad() end }),
        BaseMenuItems.Button({ controlName = "OptionsButton",
            textKey  = "TXT_KEY_MENU_OPTIONS_BUTTON",
            activate = function() OnOptions() end }),
        BaseMenuItems.Button({ controlName = "RestartGameButton",
            textKey  = "TXT_KEY_MENU_RESTART_GAME_BUTTON",
            activate = function() OnRestartGame() end }),
        BaseMenuItems.Button({ controlName = "RetireButton",
            textKey  = "TXT_KEY_RETIRE",
            activate = function() OnRetire() end }),
        BaseMenuItems.Button({ controlName = "MainMenuButton",
            textKey  = "TXT_KEY_MENU_EXIT_TO_MAIN",
            activate = mainMenuActivate }),
        BaseMenuItems.Button({ controlName = "ExitGameButton",
            textKey  = "TXT_KEY_MENU_EXIT_TO_WINDOWS",
            activate = function() OnExitGame() end }),
    }
end

-- Details tab ----------------------------------------------------------

local function leaderLabel()
    local iPlayer = Game.GetActivePlayer()
    local pPlayer = Players[iPlayer]
    local nick    = pPlayer:GetNickName()
    if Game:IsNetworkMultiPlayer() and nick ~= "" then return nick end
    if iPlayer == Game.GetActivePlayer() and PreGame.GetLeaderName(0) ~= "" then
        return PreGame.GetLeaderName(0)
    end
    local leader = GameInfo.Leaders[pPlayer:GetLeaderType()]
    return Locale.ConvertTextKey(leader.Description)
end

local function civLabel()
    local iPlayer = Game.GetActivePlayer()
    local pPlayer = Players[iPlayer]
    if iPlayer == Game.GetActivePlayer()
            and PreGame.GetCivilizationShortDescription(0) ~= "" then
        return PreGame.GetCivilizationShortDescription(0)
    end
    local info = GameInfo.Civilizations[pPlayer:GetCivilizationType()]
    return Locale.ConvertTextKey(info.ShortDescription)
end

local function eraLabel()
    local era = PreGame.GetEra()
    if era == nil then return "" end
    local row = GameInfo.Eras[era]
    if row == nil then return "" end
    return Locale.ConvertTextKey("TXT_KEY_START_ERA",
        Locale.ConvertTextKey(row.Description))
end

local function mapTypeLabel()
    local fileName = PreGame.GetMapScript()
    for row in GameInfo.MapScripts() do
        if row.FileName == fileName then
            return Locale.ConvertTextKey("TXT_KEY_AD_MAP_TYPE_SETTING",
                Locale.ConvertTextKey(row.Name))
        end
    end
    return ""
end

local function mapSizeLabel()
    local info = GameInfo.Worlds[PreGame.GetWorldSize()]
    if info == nil then return "" end
    return Locale.ConvertTextKey("TXT_KEY_AD_MAP_SIZE_SETTING",
        Locale.ConvertTextKey(info.Description))
end

local function handicapLabel()
    local info = GameInfo.HandicapInfos[PreGame.GetHandicap(Game.GetActivePlayer())]
    if info == nil then return "" end
    return Locale.ConvertTextKey("TXT_KEY_AD_HANDICAP_SETTING",
        Locale.ConvertTextKey(info.Description))
end

local function speedLabel()
    local info = GameInfo.GameSpeeds[PreGame.GetGameSpeed()]
    if info == nil then return "" end
    return Locale.ConvertTextKey("TXT_KEY_AD_GAME_SPEED_SETTING",
        Locale.ConvertTextKey(info.Description))
end

local function buildDetailsItems()
    local items = {}
    items[#items + 1] = BaseMenuItems.Text({ labelFn = leaderLabel })
    items[#items + 1] = BaseMenuItems.Text({ labelFn = civLabel })
    if PreGame.GetEra() ~= nil then
        items[#items + 1] = BaseMenuItems.Text({ labelFn = eraLabel })
    end
    items[#items + 1] = BaseMenuItems.Text({ labelFn = mapTypeLabel })
    items[#items + 1] = BaseMenuItems.Text({ labelFn = mapSizeLabel })
    items[#items + 1] = BaseMenuItems.Text({ labelFn = handicapLabel })
    items[#items + 1] = BaseMenuItems.Text({ labelFn = speedLabel })

    -- Victories: header line + one per enabled condition. Filter at build
    -- time so disabled victories don't become navigable empty entries.
    items[#items + 1] = BaseMenuItems.Text({
        labelText = Locale.ConvertTextKey("TXT_KEY_VICTORYS_FORMAT"),
    })
    for row in GameInfo.Victories() do
        if PreGame.IsVictory(row.ID) then
            items[#items + 1] = BaseMenuItems.Text({
                labelText = Locale.ConvertTextKey(row.Description),
            })
        end
    end

    -- Enabled GameOptions, matching PopulateGameOptions' filter.
    local conditions = { Visible = 1 }
    if Game:IsNetworkMultiPlayer() then
        conditions.SupportsMultiplayer = 1
    else
        conditions.SupportsSinglePlayer = 1
    end
    for option in GameInfo.GameOptions(conditions) do
        local saved = PreGame.GetGameOption(option.Type)
        if saved ~= nil and saved == 1 then
            items[#items + 1] = BaseMenuItems.Text({
                labelText = Locale.ConvertTextKey(option.Description),
            })
        end
    end

    return items
end

-- Mods tab -------------------------------------------------------------

local function buildModsItems()
    local active = Modding.GetActivatedMods()
    if active == nil or #active == 0 then
        return {
            BaseMenuItems.Text({
                textKey = "TXT_KEY_CIVVACCESS_GAMEMENU_NO_MODS",
            }),
        }
    end
    local sorted = {}
    for _, v in ipairs(active) do
        local title = Modding.GetModProperty(v.ID, v.Version, "Name") or ""
        sorted[#sorted + 1] = { title = title, version = v.Version }
    end
    table.sort(sorted,
        function(a, b) return Locale.Compare(a.title, b.title) == -1 end)

    local items = {}
    for _, m in ipairs(sorted) do
        items[#items + 1] = BaseMenuItems.Text({
            labelText = string.format("%s (v. %d)", m.title, m.version),
        })
    end
    return items
end

-- Install --------------------------------------------------------------

local handler

local function wrappedShowHide(bIsHide, bIsInit)
    local ok, err = pcall(priorShowHide, bIsHide, bIsInit)
    if not ok then
        Log.error("GameMenuAccess: priorShowHide failed: " .. tostring(err))
    end
    if bIsHide then
        -- If the confirm sub-handler is still around (rare: shown at the
        -- moment the whole menu dequeues), drop it so the stack doesn't
        -- outlive its Context.
        HandlerStack.removeByName("GameMenuExitConfirm", false)
    end
end

handler = BaseMenu.install(ContextPtr, {
    name          = "GameMenu",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_GAME_MENU"),
    priorShowHide = wrappedShowHide,
    priorInput    = priorInput,
    onShow        = function(h)
        showMainContainer()
        h.setItems(buildActionsItems(), ACTIONS_TAB)
        h.setItems(buildDetailsItems(), DETAILS_TAB)
        h.setItems(buildModsItems(),    MODS_TAB)
    end,
    tabs = {
        {
            name      = "TXT_KEY_CIVVACCESS_GAMEMENU_ACTIONS_TAB",
            showPanel = showMainContainer,
            items     = {
                BaseMenuItems.Button({ controlName = "ReturnButton",
                    textKey  = "TXT_KEY_MENU_RETURN_TO_GAME",
                    activate = function() OnReturn() end }),
            },
        },
        {
            name      = "TXT_KEY_CIVVACCESS_GAMEMENU_DETAILS_TAB",
            showPanel = showDetailsPanel,
            items     = { BaseMenuItems.Text({ labelText = "" }) },
            onActivate = function(h)
                h.setItems(buildDetailsItems(), DETAILS_TAB)
            end,
        },
        {
            name      = "TXT_KEY_CIVVACCESS_GAMEMENU_MODS_TAB",
            showPanel = showModsPanel,
            items     = { BaseMenuItems.Text({ labelText = "" }) },
            onActivate = function(h)
                h.setItems(buildModsItems(), MODS_TAB)
            end,
        },
    },
})
