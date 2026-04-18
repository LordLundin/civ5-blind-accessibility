-- ModsBrowser accessibility wiring. This context is a four-button shell
-- around the installed-mods sub-panel (InstalledPanel, not yet handled);
-- the Next / Workshop / Back actions are global functions, but SmallButton1
-- (Delete) is wired to a LuaEvents signal that sub-contexts dispatch
-- (LuaEvents.OnModBrowserDeleteButtonClicked), and its caption + tooltip
-- are pushed in from sub-contexts via LuaEvents.ModBrowserSetDeleteButtonState
-- -> SetButtonState(button, label, visible, enabled, caption, tooltip).
-- We read the current caption via labelFn so a sub that relabels SmallButton1
-- from "Delete" to "Disable" etc. is reflected in speech. Visibility /
-- IsDisabled are already respected by Button's shared isNavigable /
-- isActivatable.
--
-- Workshop (SmallButton2) opens the Steam overlay to the Workshop page
-- when the overlay is enabled; base's anonymous ShowHide hides it when
-- the overlay is off. We replicate that gate in onShow since the base's
-- ShowHide registration is anonymous and BaseMenu.install's wrapper
-- overwrites it.

include("CivVAccess_FrontendCommon")

local priorInput = InputHandler

-- Cross-Context signal for InstalledPanelAccess: the child LuaContext's own
-- ShowHide only fires at Context init (Hidden="0" in ModsBrowser.xml), not
-- when the parent popup becomes visible, so InstalledPanel's handler cannot
-- key off its own ShowHide to stack above ModsBrowser. We fire from our
-- priorShowHide here; InstalledPanelAccess listens and defer-pushes its
-- handler so it lands above this one.
local function onShowHide(bIsHide, bIsInit)
    LuaEvents.CivVAccessModsBrowserVisibilityChanged(not bIsHide)
end

-- Cross-Context activation for shell buttons exposed as picker-tail items
-- in InstalledPanelAccess. Next and Workshop's bodies reference
-- Controls.ModsMenu / the Steam URL string that lives in this Context;
-- forwarding through a LuaEvent keeps the call in the owning sandbox.
LuaEvents.CivVAccessModsBrowserNext.Add(function()
    OnNextButtonClicked()
end)
LuaEvents.CivVAccessModsBrowserWorkshop.Add(function()
    OnWorkshopButtonClicked()
end)
LuaEvents.CivVAccessModsBrowserBack.Add(function()
    NavigateBack()
end)

local function deleteButtonLabel()
    local l = Controls.SmallButton1Label
    if l ~= nil then
        local ok, t = pcall(function() return l:GetText() end)
        if ok and t ~= nil and t ~= "" then return tostring(t) end
    end
    return Text.key("TXT_KEY_MODDING_DELETEMOD")
end

local function deleteButtonTooltip()
    local b = Controls.SmallButton1
    if b == nil then return nil end
    local ok, t = pcall(function() return b:GetToolTipString() end)
    if ok and t ~= nil and t ~= "" then return tostring(t) end
    return nil
end

BaseMenu.install(ContextPtr, {
    name        = "ModsBrowser",
    displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MODS_BROWSER"),
    priorInput    = priorInput,
    priorShowHide = onShowHide,
    onShow      = function(h)
        -- Replicates the anonymous ShowHide (ModsBrowser.lua line 36).
        if Controls.SmallButton2 ~= nil then
            Controls.SmallButton2:SetHide(not Steam.IsOverlayEnabled())
        end
    end,
    items = {
        BaseMenuItems.Button({ controlName = "SmallButton1",
            labelFn    = deleteButtonLabel,
            tooltipFn  = deleteButtonTooltip,
            activate   = function() LuaEvents.OnModBrowserDeleteButtonClicked() end }),
        BaseMenuItems.Button({ controlName = "SmallButton2",
            textKey    = "TXT_KEY_MODDING_WORKSHOP",
            tooltipKey = "TXT_KEY_MODDING_WORKSHOP_TT",
            activate   = function() OnWorkshopButtonClicked() end }),
        BaseMenuItems.Button({ controlName = "LargeButton",
            textKey    = "TXT_KEY_MODDING_NEXT",
            activate   = function() OnNextButtonClicked() end }),
        BaseMenuItems.Button({ controlName = "BackButton",
            textKey    = "TXT_KEY_MODDING_BACK",
            activate   = function() NavigateBack() end }),
    },
})
