-- OptionsMenu accessibility wiring. Five-tab form. The screen's own
-- OnCategory(which) toggles panel visibility and highlight boxes; we reuse
-- it directly rather than duplicate SetHide chains.
--
-- Tooltip keys are read from OptionsMenu.xml's ToolTip attribute on each
-- control (or its parent Label for widgets whose tooltip is on the grouping
-- container). Missing tooltips are fine -- FormHandler just appends nothing.
--
-- Items are ordered roughly top-to-bottom, left-to-right as they appear in
-- the shipped UI. Hidden-by-platform widgets (tablet-only sliders, LAN-
-- specific controls when multiplayer category is off) are still listed --
-- FormHandler's isNavigable skips them when IsHidden() returns true, so the
-- user never lands on something that would not accept input.
--
-- The three bottom buttons (Defaults / Cancel / Accept) live outside every
-- per-tab Container and stay visible regardless of which tab is active, so
-- they are appended to each tab's item list below. The GraphicsChangedPopup
-- and Countdown modals that OnOK / OnApplyRes raise are nested widgets in
-- the same Context; their handlers are pushed on top of the form handler
-- and driven by wrapping the engine's show / close globals (below).

include("CivVAccess_FrontendCommon")
include("CivVAccess_FormHandler")
include("CivVAccess_SimpleListHandler")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

-- Appended to every tab's item list so the three bottom buttons stay
-- reachable from any tab (matches their always-visible placement in XML).
local commonButtons = {
    { kind = "button", controlName = "DefaultButton",
      textKey    = "TXT_KEY_OPSCREEN_DEFAULTS_BUTTON",
      tooltipKey = "TXT_KEY_OPSCREEN_DEFAULTS_BUTTON_TT",
      activate   = function() OnDefault() end },
    { kind = "button", controlName = "CancelButton",
      textKey  = "TXT_KEY_OPSCREEN_CANCEL_BUTTON",
      activate = function() OnCancel() end },
    { kind = "button", controlName = "AcceptButton",
      textKey    = "TXT_KEY_OPSCREEN_SAVE_BUTTON",
      tooltipKey = "TXT_KEY_OPSCREEN_SAVE_BUTTON_TT",
      activate   = function() OnOK() end },
}

local function withButtons(items)
    for _, b in ipairs(commonButtons) do items[#items + 1] = b end
    return items
end

FormHandler.install(ContextPtr, {
    name             = "OptionsMenu",
    displayName      = Text.key("TXT_KEY_CIVVACCESS_SCREEN_OPTIONS"),
    priorShowHide    = priorShowHide,
    priorInput       = priorInput,
    focusParkControl = "CancelButton",
    tabs = {
        {
            name      = "TXT_KEY_GAME_OPTIONS",
            showPanel = function() OnCategory(1) end,
            items     = withButtons({
                -- WheelSteps=10 per XML; use 0.1 so each press advances
                -- the integer-second label visibly (default 0.01 would
                -- take 5-10 presses before the label changes).
                { kind = "slider",   controlName = "Tooltip1TimerSlider",
                  labelControlName = "Tooltip1TimerLength",
                  textKey    = "TXT_KEY_OPSCREEN_TOOLTIP_1_TIMER_LENGTH",
                  tooltipKey = "TXT_KEY_OPSCREEN_TOOLTIP_1_TIMER_LENGTH_TT",
                  step = 0.1, bigStep = 0.2 },
                { kind = "pulldown", controlName = "TutorialPull",
                  textKey    = "TXT_KEY_OPSCREEN_TUTORIAL_LEVEL",
                  tooltipKey = "TXT_KEY_OPSCREEN_TUTORIAL_LEVEL_TT" },
                { kind = "button",   controlName = "ResetTutorialButton",
                  textKey    = "TXT_KEY_OPSCREEN_RESET_TUTORIAL",
                  tooltipKey = "TXT_KEY_OPSCREEN_RESET_TUTORIAL_TT",
                  activate   = function() OnResetTutorial() end },
                { kind = "checkbox", controlName = "SinglePlayerAutoEndTurnCheckBox",
                  textKey    = "TXT_KEY_OPSCREEN_SPLAYER_AUTO_END_TURN",
                  tooltipKey = "TXT_KEY_OPSCREEN_SPLAYER_AUTO_END_TURN_TT" },
                { kind = "checkbox", controlName = "MultiplayerAutoEndTurnCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_MULTIPLAYER_AUTO_END_TURN",
                  tooltipKey = "TXT_KEY_OPSCREEN_MULTIPLAYER_AUTO_END_TURN_TT" },
                { kind = "checkbox", controlName = "SPQuickCombatCheckBox",
                  textKey    = "TXT_KEY_OPSCREEN_SPLAYER_QUICK_COMBAT",
                  tooltipKey = "TXT_KEY_OPSCREEN_SPLAYER_QUICK_COMBAT_TT" },
                { kind = "checkbox", controlName = "SPQuickMovementCheckBox",
                  textKey    = "TXT_KEY_OPSCREEN_SPLAYER_QUICK_MOVEMENT",
                  tooltipKey = "TXT_KEY_OPSCREEN_SPLAYER_QUICK_MOVEMENT_TT" },
                { kind = "checkbox", controlName = "MPQuickCombatCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_MULTIPLAYER_QUICK_COMBAT",
                  tooltipKey = "TXT_KEY_OPSCREEN_MULTIPLAYER_QUICK_COMBAT_TT" },
                { kind = "checkbox", controlName = "MPQuickMovementCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_MULTIPLAYER_QUICK_MOVEMENT",
                  tooltipKey = "TXT_KEY_OPSCREEN_MULTIPLAYER_QUICK_MOVEMENT_TT" },
                { kind = "checkbox", controlName = "AutoWorkersDontReplaceCB",
                  textKey    = "TXT_KEY_OPSCREEN_AUTO_WORKERS_DONT_REPLACE",
                  tooltipKey = "TXT_KEY_OPSCREEN_AUTO_WORKERS_DONT_REPLACE_TT" },
                { kind = "checkbox", controlName = "AutoWorkersDontRemoveFeaturesCB",
                  textKey    = "TXT_KEY_OPSCREEN_AUTO_WORKERS_DONT_REMOVE_FEATURES",
                  tooltipKey = "TXT_KEY_OPSCREEN_AUTO_WORKERS_DONT_REMOVE_FEATURES_TT" },
                { kind = "checkbox", controlName = "NoRewardPopupsCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_NO_REWARD_POPUPS",
                  tooltipKey = "TXT_KEY_OPSCREEN_NO_REWARD_POPUPS_TT" },
                { kind = "checkbox", controlName = "NoTileRecommendationsCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_NO_TILE_RECOMMENDATIONS",
                  tooltipKey = "TXT_KEY_OPSCREEN_NO_TILE_RECOMMENDATIONS_TT" },
                { kind = "checkbox", controlName = "CivilianYieldsCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_CIVILIAN_YIELDS",
                  tooltipKey = "TXT_KEY_OPSCREEN_CIVILIAN_YIELDS_TT" },
                { kind = "checkbox", controlName = "NoBasicHelpCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_NO_BASIC_HELP",
                  tooltipKey = "TXT_KEY_OPSCREEN_NO_BASIC_HELP_TT" },
                { kind = "checkbox", controlName = "QuickSelectionAdvCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_QUICK_SELECTION_ADVANCE",
                  tooltipKey = "TXT_KEY_OPSCREEN_QUICK_SELECTION_ADVANCE_TT" },
            }),
        },
        {
            name      = "TXT_KEY_INTERFACE_OPTIONS",
            showPanel = function() OnCategory(2) end,
            items     = withButtons({
                { kind = "textfield", controlName = "AutosaveTurnsEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURNS_FOR_AUTOSAVES",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURNS_FOR_AUTOSAVES_TT",
                  priorCallback = OnAutosaveTurnsChanged },
                { kind = "textfield", controlName = "AutosaveMaxEdit",
                  textKey       = "TXT_KEY_OPSCREEN_MAX_AUTOSAVES_KEPT",
                  tooltipKey    = "TXT_KEY_OPSCREEN_MAX_AUTOSAVES_KEPT_TT",
                  priorCallback = OnAutosaveMaxChanged },
                { kind = "pulldown", controlName = "BindMousePull",
                  textKey    = "TXT_KEY_BIND_MOUSE",
                  tooltipKey = "TXT_KEY_BIND_MOUSE_TT" },
                { kind = "checkbox", controlName = "ZoomCheck",
                  textKey    = "TXT_KEY_OPSCREEN_DYNAMIC_CAMERA_ZOOM",
                  tooltipKey = "TXT_KEY_OPSCREEN_DYNAMIC_CAMERA_ZOOM_TT" },
                { kind = "checkbox", controlName = "PolicyInfo",
                  textKey    = "TXT_KEY_OPSCREEN_SHOW_ALL_POLICY_INFO",
                  tooltipKey = "TXT_KEY_OPSCREEN_SHOW_ALL_POLICY_INFO_TT" },
                { kind = "checkbox", controlName = "AutoUnitCycleCheck",
                  textKey    = "TXT_KEY_AUTO_UNIT_CYCLE",
                  tooltipKey = "TXT_KEY_AUTO_UNIT_CYCLE_TT" },
                { kind = "checkbox", controlName = "ScoreListCheck",
                  textKey    = "TXT_KEY_OPSCREEN_SCORE_LIST",
                  tooltipKey = "TXT_KEY_OPSCREEN_SCORE_LIST_TT" },
                { kind = "checkbox", controlName = "MPScoreListCheck",
                  textKey    = "TXT_KEY_OPSCREEN_MP_SCORE_LIST",
                  tooltipKey = "TXT_KEY_OPSCREEN_MP_SCORE_LIST_TT" },
                { kind = "checkbox", controlName = "EnableMapInertiaCheck",
                  textKey    = "TXT_KEY_OPSCREEN_ENABLE_MAP_INERTIA",
                  tooltipKey = "TXT_KEY_OPSCREEN_ENABLE_MAP_INERTIA_TT" },
                { kind = "checkbox", controlName = "SkipIntroVideoCheck",
                  textKey    = "TXT_KEY_OPSCREEN_SKIP_INTRO_VIDEO",
                  tooltipKey = "TXT_KEY_OPSCREEN_SKIP_INTRO_VIDEO_TT" },
                { kind = "checkbox", controlName = "AutoUIAssetsCheck",
                  textKey    = "TXT_KEY_OPSCREEN_AUTOSIZE_UI",
                  tooltipKey = "TXT_KEY_OPSCREEN_AUTOSIZE_UI_TT" },
                { kind = "checkbox", controlName = "SmallUIAssetsCheck",
                  textKey    = "TXT_KEY_OPSCREEN_USE_SMALL_UI",
                  tooltipKey = "TXT_KEY_OPSCREEN_USE_SMALL_UI_TT" },
                { kind = "pulldown", controlName = "LanguagePull",
                  textKey    = "TXT_KEY_OPSCREEN_SELECT_LANG" },
                { kind = "pulldown", controlName = "SpokenLanguagePull",
                  textKey    = "TXT_KEY_OPSCREEN_SELECT_SPOKEN_LANG" },
                -- WheelSteps=10 per XML for both drag and pinch sliders.
                { kind = "slider",   controlName = "DragSpeedSlider",
                  labelControlName = "DragSpeedValue",
                  textKey    = "TXT_KEY_DRAG_SPEED",
                  tooltipKey = "TXT_KEY_DRAG_SPEED_TT",
                  step = 0.1, bigStep = 0.2 },
                { kind = "slider",   controlName = "PinchSpeedSlider",
                  labelControlName = "PinchSpeedValue",
                  textKey    = "TXT_KEY_PINCH_SPEED",
                  tooltipKey = "TXT_KEY_PINCH_SPEED_TT",
                  step = 0.1, bigStep = 0.2 },
            }),
        },
        {
            name      = "TXT_KEY_VIDEO_OPTIONS",
            showPanel = function() OnCategory(3) end,
            items     = withButtons({
                { kind = "pulldown", controlName = "FSResolutionPull",
                  textKey = "TXT_KEY_CIVVACCESS_OPSCREEN_RESOLUTION_FS" },
                { kind = "pulldown", controlName = "WResolutionPull",
                  textKey = "TXT_KEY_CIVVACCESS_OPSCREEN_RESOLUTION_W" },
                { kind = "pulldown", controlName = "MSAAPull",
                  textKey = "TXT_KEY_OPSCREEN_MSAA" },
                { kind = "checkbox", controlName = "FullscreenCheck",
                  textKey = "TXT_KEY_OPSCREEN_FULLSCREEN" },
                { kind = "button",   controlName = "ApplyResButton",
                  textKey    = "TXT_KEY_OPSCREEN_APPLY_RESOLUTION",
                  tooltipKey = "TXT_KEY_OPSCREEN_APPLY_RESOLUTION_TT",
                  activate   = function() OnApplyRes() end },
                { kind = "checkbox", controlName = "VSyncCheck",
                  textKey    = "TXT_KEY_OPSCREEN_VSYNC",
                  tooltipKey = "TXT_KEY_OPSCREEN_RESTART_REQ_TT" },
                { kind = "checkbox", controlName = "HDStratCheck",
                  textKey    = "TXT_KEY_OPSCREEN_HIGH_DETAIL_STRAT_VIEW",
                  tooltipKey = "TXT_KEY_OPSCREEN_HIGH_DETAIL_STRAT_VIEW_TT" },
                { kind = "checkbox", controlName = "GPUDecodeCheck",
                  textKey    = "TXT_KEY_OPSCREEN_GPU_TEXTURE_DECODE",
                  tooltipKey = "TXT_KEY_OPSCREEN_GPU_TEXTURE_DECODE_TT" },
                { kind = "pulldown", controlName = "LeaderPull",
                  textKey = "TXT_KEY_OPSCREEN_LEADER_QUALITY" },
                { kind = "pulldown", controlName = "OverlayPull",
                  textKey = "TXT_KEY_OPSCREEN_OVERLAY_DETAIL" },
                { kind = "pulldown", controlName = "ShadowPull",
                  textKey = "TXT_KEY_OPSCREEN_SHADOW_QUALITY" },
                { kind = "pulldown", controlName = "FOWPull",
                  textKey = "TXT_KEY_OPSCREEN_FOW_QUALITY" },
                { kind = "pulldown", controlName = "TerrainDetailPull",
                  textKey = "TXT_KEY_OPSCREEN_TERRAIN_DETAIL_LEVEL" },
                { kind = "pulldown", controlName = "TerrainTessPull",
                  textKey = "TXT_KEY_OPSCREEN_TERRAIN_TESS_LEVEL" },
                { kind = "pulldown", controlName = "TerrainShadowPull",
                  textKey = "TXT_KEY_OPSCREEN_TERRAIN_SHADOW_QUALITY" },
                { kind = "pulldown", controlName = "WaterPull",
                  textKey = "TXT_KEY_OPSCREEN_WATER_QUALITY" },
                { kind = "pulldown", controlName = "TextureQualityPull",
                  textKey = "TXT_KEY_OPSCREEN_TEXTURE_QUALITY" },
            }),
        },
        {
            name      = "TXT_KEY_AUDIO_OPTIONS",
            showPanel = function() OnCategory(4) end,
            items     = withButtons({
                { kind = "slider", controlName = "MusicVolumeSlider",
                  labelControlName = "MusicVolumeSliderValue",
                  textKey = "TXT_KEY_OPSCREEN_MUSIC_SLIDER" },
                { kind = "slider", controlName = "EffectsVolumeSlider",
                  labelControlName = "EffectsVolumeSliderValue",
                  textKey = "TXT_KEY_OPSCREEN_SF_SLIDER" },
                { kind = "slider", controlName = "AmbienceVolumeSlider",
                  labelControlName = "AmbienceVolumeSliderValue",
                  textKey = "TXT_KEY_OPSCREEN_AMBIANCE_SLIDER" },
                { kind = "slider", controlName = "SpeechVolumeSlider",
                  labelControlName = "SpeechVolumeSliderValue",
                  textKey = "TXT_KEY_OPSCREEN_SPEECH_SLIDER" },
            }),
        },
        {
            name      = "TXT_KEY_MULTIPLAYER_OPTIONS",
            showPanel = function() OnCategory(5) end,
            items     = withButtons({
                { kind = "checkbox", controlName = "TurnNotifySteamInviteCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_STEAM_INVITE",
                  tooltipKey = "TXT_KEY_OPSCREEN_TURN_NOTIFY_STEAM_INVITE_TT" },
                { kind = "checkbox", controlName = "TurnNotifyEmailCheckbox",
                  textKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_EMAIL",
                  tooltipKey = "TXT_KEY_OPSCREEN_TURN_NOTIFY_EMAIL_TT" },
                { kind = "textfield", controlName = "TurnNotifyEmailAddressEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_EMAIL_ADDRESS",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_EMAIL_ADDRESS_TT",
                  priorCallback = OnTurnNotifyEmailAddressChanged },
                { kind = "textfield", controlName = "TurnNotifySmtpEmailEdit",
                  textKey       = "TXT_KEY_CIVVACCESS_OPSCREEN_SMTP_FROM_EMAIL",
                  priorCallback = OnTurnNotifySmtpEmailChanged },
                { kind = "textfield", controlName = "TurnNotifySmtpHostEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_HOST",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_HOST_TT",
                  priorCallback = OnTurnNotifySmtpHostChanged },
                { kind = "checkbox", controlName = "TurnNotifySmtpTLS",
                  textKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_TLS",
                  tooltipKey = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_TLS_TT" },
                { kind = "textfield", controlName = "TurnNotifySmtpPortEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_PORT",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_PORT_TT",
                  priorCallback = OnTurnNotifySmtpPortChanged },
                { kind = "textfield", controlName = "TurnNotifySmtpUserEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_USERNAME",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_USERNAME_TT",
                  priorCallback = OnTurnNotifySmtpUsernameChanged },
                { kind = "textfield", controlName = "TurnNotifySmtpPassEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_PASSWORD",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_PASSWORD_TT",
                  priorCallback = ValidateSmtpPassword },
                { kind = "textfield", controlName = "TurnNotifySmtpPassRetypeEdit",
                  textKey       = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_RETYPE_PASSWORD",
                  tooltipKey    = "TXT_KEY_OPSCREEN_TURN_NOTIFY_SMTP_RETYPE_PASSWORD_TT",
                  priorCallback = ValidateSmtpPassword },
                { kind = "textfield", controlName = "LANNickNameEdit",
                  textKey       = "TXT_KEY_MP_NICK_NAME",
                  priorCallback = OnLANNickNameChanged },
            }),
        },
    },
})

-- Modal popup wiring -----------------------------------------------------
--
-- OptionsMenu raises two modals inside its own Context:
--   * GraphicsChangedPopup -- single OK when non-resolution graphics
--     options were changed at Accept time.
--   * Countdown            -- Yes/No with a 20-second auto-revert timer,
--                             raised after Apply Resolution or a Language
--                             pulldown selection.
--
-- Both are driven by wrapping the engine's show / close globals rather
-- than watching widget visibility: the globals are the choke points the
-- game itself funnels through. The close wrappers also re-install
-- TickPump, which the game's ClearUpdate() unhooks (ShowResolutionCountdown
-- / ShowLanguageCountdown call SetUpdate(OnUpdate), clobbering the pump).
-- Without that re-install, later TickPump.runOnce callbacks (e.g. the
-- textfield edit-mode's deferred TakeFocus) would silently never fire.
--
-- Mouse clicks on the Countdown / GraphicsChangedOK buttons go through
-- the engine's RegisterCallback, which captured the pre-wrap globals and
-- therefore bypasses our wrappers. Keyboard activation (our items' own
-- activate fn) and engine-internal calls (OnUpdate -> OnCountdownNo on
-- timer expiry, OnApplyRes -> ShowResolutionCountdown) both resolve the
-- global fresh at call time and land on the wrapped version.

-- Set by our popup items' activate fn; nil means the close handler was
-- invoked from engine-internal code (the 20s timer expiry via OnUpdate).
-- Distinguishing is necessary because the expiry path wants a spoken
-- "time expired, reverted" while user-clicked paths do not.
local countdownUserAction

local graphicsPopup = SimpleListHandler.create({
    name        = "OptionsGraphicsChanged",
    displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_FRONT_END_POPUP"),
    preamble    = Text.key("TXT_KEY_OPSCREEN_VDOP_RESTART"),
    items = {
        { controlName = "GraphicsChangedOK",
          textKey     = "TXT_KEY_OK_BUTTON",
          activate    = function() OnGraphicsChangedOK() end },
    },
})

-- No first so the initial cursor lands on the safer option: accidentally
-- accepting a resolution / language change is not recoverable without
-- another trip through this flow; accidentally reverting is.
local countdownPopup = SimpleListHandler.create({
    name        = "OptionsCountdown",
    displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_FRONT_END_POPUP"),
    preamble    = function()
        local msg = ""
        if Controls.CountdownMessage then
            msg = Controls.CountdownMessage:GetText() or ""
        end
        return Text.format("TXT_KEY_CIVVACCESS_OPTIONS_COUNTDOWN_INTRO", msg)
    end,
    items = {
        { controlName = "CountNo",
          labelFn     = function(c) return c:GetText() end,
          activate    = function()
              countdownUserAction = "no"
              OnCountdownNo()
          end },
        { controlName = "CountYes",
          labelFn     = function(c) return c:GetText() end,
          activate    = function()
              countdownUserAction = "yes"
              OnCountdownYes()
          end },
    },
})

local function maybePushGraphicsPopup()
    if Controls.GraphicsChangedPopup
       and not Controls.GraphicsChangedPopup:IsHidden() then
        HandlerStack.push(graphicsPopup)
    end
end

local origShowResolutionCountdown = ShowResolutionCountdown
function ShowResolutionCountdown()
    origShowResolutionCountdown()
    HandlerStack.push(countdownPopup)
end

local origShowLanguageCountdown = ShowLanguageCountdown
function ShowLanguageCountdown()
    origShowLanguageCountdown()
    HandlerStack.push(countdownPopup)
end

local origOnCountdownYes = OnCountdownYes
function OnCountdownYes()
    countdownUserAction = nil
    origOnCountdownYes()
    -- Language Yes reloads the UI (SystemUpdateUI), so ContextPtr may be
    -- tearing down. pcall the re-install so a dying Context doesn't log.
    pcall(function() TickPump.install(ContextPtr) end)
    HandlerStack.removeByName(countdownPopup.name, true)
    -- OnOK with both flags set raises the graphics popup underneath the
    -- countdown; hand off once countdown closes.
    maybePushGraphicsPopup()
end

local origOnCountdownNo = OnCountdownNo
function OnCountdownNo()
    local wasUserAction = countdownUserAction ~= nil
    countdownUserAction = nil
    origOnCountdownNo()
    pcall(function() TickPump.install(ContextPtr) end)
    if wasUserAction then
        HandlerStack.removeByName(countdownPopup.name, true)
    else
        -- Timer expiry: announce the revert, then pop silently so the
        -- form's re-activate announcement doesn't interrupt mid-phrase.
        SpeechPipeline.speakInterrupt(
            Text.key("TXT_KEY_CIVVACCESS_OPTIONS_COUNTDOWN_EXPIRED"))
        HandlerStack.removeByName(countdownPopup.name, false)
    end
    maybePushGraphicsPopup()
end

local origOnOK = OnOK
function OnOK()
    origOnOK()
    -- Countdown takes priority when both popups are revealed (the
    -- countdown's close wrappers hand off to the graphics popup).
    if Controls.Countdown and not Controls.Countdown:IsHidden() then return end
    maybePushGraphicsPopup()
end

local origOnGraphicsChangedOK = OnGraphicsChangedOK
function OnGraphicsChangedOK()
    origOnGraphicsChangedOK()
    HandlerStack.removeByName(graphicsPopup.name, true)
end
