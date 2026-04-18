-- WorldPicker accessibility wiring. Six world-size buttons plus Esc ->
-- SetHide. Base's InputHandler is a global (routes Esc to
-- ContextPtr:SetHide); each *ButtonClick is a global that fires
-- Events.SerialEventStartGame with the matching WorldSizeType. The
-- source file marks this screen as a placeholder, so it may never
-- appear in the normal flow; wiring it is cheap insurance.

include("CivVAccess_FrontendCommon")

local priorInput = InputHandler

BaseMenu.install(ContextPtr, {
    name        = "WorldPicker",
    displayName = Text.key("TXT_KEY_CIVVACCESS_SCREEN_WORLD_PICKER"),
    priorInput  = priorInput,
    items = {
        BaseMenuItems.Button({ controlName = "DuelWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_DUEL",
            activate = function() DuelWorldSizeButtonClick() end }),
        BaseMenuItems.Button({ controlName = "TinyWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_TINY",
            activate = function() TinyWorldSizeButtonClick() end }),
        BaseMenuItems.Button({ controlName = "SmallWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_SMALL",
            activate = function() SmallWorldSizeButtonClick() end }),
        BaseMenuItems.Button({ controlName = "StandardWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_STANDARD",
            activate = function() StandardWorldSizeButtonClick() end }),
        BaseMenuItems.Button({ controlName = "LargeWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_LARGE",
            activate = function() LargeWorldSizeButtonClick() end }),
        BaseMenuItems.Button({ controlName = "HugeWorldSizeButton",
            textKey  = "TXT_KEY_WORLD_HUGE",
            activate = function() HugeWorldSizeButtonClick() end }),
    },
})
