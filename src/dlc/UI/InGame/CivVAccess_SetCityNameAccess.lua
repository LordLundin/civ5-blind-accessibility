-- SetCityName popup (rename city). Three items: the city-name EditBox, the
-- Accept button (commits via Network.SendRenameCity), and the Cancel button.
-- The base file's EditBox callback is Validate, which toggles the Accept
-- button's disabled state but does not itself close the popup, so no
-- commitFn is supplied: Enter in the edit sub-handler just returns the
-- user to the form, where they can navigate to Accept. Escape at the form
-- layer falls through to the screen's InputHandler which calls OnCancel.

include("CivVAccess_InGameCommon")
include("CivVAccess_FormHandler")
include("CivVAccess_TextFieldSubHandler")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

FormHandler.install(ContextPtr, {
    name          = "SetCityName",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_SET_CITY_NAME"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    items = {
        { kind = "textfield", controlName = "EditCityName",
          textKey       = "TXT_KEY_PRODPANEL_CITY_NAME",
          priorCallback = Validate },
        { kind = "button",   controlName = "AcceptButton",
          textKey  = "TXT_KEY_ACCEPT_BUTTON",
          activate = function() OnAccept() end },
        { kind = "button",   controlName = "CancelButton",
          textKey  = "TXT_KEY_CANCEL_BUTTON",
          activate = function() OnCancel() end },
    },
})
