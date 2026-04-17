-- SetUnitName popup (rename a unit / Great Person). Parallel to
-- SetCityName but the base file's InputHandler catches Enter and calls
-- OnAccept directly, so we route Enter in the edit sub-handler to the
-- same OnAccept as a commitFn. That way the user can type and press
-- Enter to rename without arrowing to Accept.

include("CivVAccess_InGameCommon")
include("CivVAccess_FormHandler")
include("CivVAccess_TextFieldSubHandler")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

FormHandler.install(ContextPtr, {
    name          = "SetUnitName",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_SET_UNIT_NAME"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    items = {
        { kind = "textfield", controlName = "EditUnitName",
          textKey       = "TXT_KEY_UNIT_NAME",
          priorCallback = Validate,
          commitFn      = function() OnAccept() end },
        { kind = "button",   controlName = "AcceptButton",
          textKey  = "TXT_KEY_ACCEPT_BUTTON",
          activate = function() OnAccept() end },
        { kind = "button",   controlName = "CancelButton",
          textKey  = "TXT_KEY_CANCEL_BUTTON",
          activate = function() OnCancel() end },
    },
})
