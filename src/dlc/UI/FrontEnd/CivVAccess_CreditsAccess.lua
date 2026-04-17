-- Credits accessibility wiring. Scrolling-text splash with one BackButton.
-- Empty-items SimpleListHandler: announces the screen name on entry; Esc
-- routes through to the base InputHandler -> OnBack. The base handler also
-- treats Enter as back, but our VK_RETURN binding shadows it silently; Esc
-- is the back-out key here.

include("CivVAccess_FrontendCommon")
include("CivVAccess_SimpleListHandler")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

SimpleListHandler.install(ContextPtr, {
    name          = "Credits",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_CREDITS"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    items         = {},
})
