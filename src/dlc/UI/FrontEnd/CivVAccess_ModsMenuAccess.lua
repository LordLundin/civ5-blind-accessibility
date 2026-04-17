-- ModsMenu accessibility wiring. SinglePlayer / MultiPlayer buttons get
-- SetDisabled based on mod-property gating, so we want the handler to walk
-- disabled items and announce them as "disabled" without firing activate.
-- ShowHide and InputHandler in the game file are anonymous; priorInput
-- reproduces the original Esc -> NavigateBack routing.

include("CivVAccess_FrontendCommon")
include("CivVAccess_ModListPreamble")

Menu.install(ContextPtr, {
    name        = "ModsMenu",
    displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MODS_MENU"),
    preamble    = ModListPreamble.fn(),
    priorInput  = Menu.escOnlyInput(NavigateBack),
    items = {
        MenuItems.Button({ controlName = "SinglePlayerButton",
            textKey  = "TXT_KEY_MODDING_SINGLE_PLAYER",
            activate = function() OnSinglePlayerClick() end }),
        MenuItems.Button({ controlName = "MultiPlayerButton",
            textKey  = "TXT_KEY_MODDING_MULTIPLAYER",
            activate = function() OnMultiPlayerClick() end }),
        MenuItems.Button({ controlName = "BackButton",
            textKey  = "TXT_KEY_MODDING_MENU_BACK",
            activate = function() NavigateBack() end }),
    },
})
