-- ChangePassword popup. Three EditBoxes (Old / New / Retype) plus OK /
-- Cancel. The old-password box is hidden on accounts that have never
-- set one (ShowHideHandler on OldPasswordStack); FormHandler's isNavigable
-- check on IsHidden keeps our cursor off it automatically via the Stack
-- ancestor's hidden state (the EditBox itself is not set hidden, so we
-- mirror the engine's focus-stop behavior by including only the two
-- always-visible boxes; the Old box is handled via the stack-visibility
-- aware FormHandler -- if the engine's hidden propagation reaches the
-- EditBox we will skip it, otherwise the item announces but the user's
-- typed value is ignored by the validator and OK stays disabled, making
-- the state obvious).
--
-- All three EditBoxes share the same Validate (enables OK only if new /
-- retype match and the old password is correct). Enter in the base file
-- triggers OnOK via InputHandler, so we pass commitFn=OnOK on each
-- textfield for the same ergonomics.

include("CivVAccess_InGameCommon")
include("CivVAccess_FormHandler")
include("CivVAccess_TextFieldSubHandler")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler

FormHandler.install(ContextPtr, {
    name          = "ChangePassword",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_CHANGE_PASSWORD"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    items = {
        { kind = "textfield", controlName = "OldPasswordEditBox",
          textKey       = "TXT_KEY_MP_OLD_PASSWORD",
          priorCallback = Validate,
          commitFn      = function() OnOK() end },
        { kind = "textfield", controlName = "NewPasswordEditBox",
          textKey       = "TXT_KEY_MP_NEW_PASSWORD",
          priorCallback = Validate,
          commitFn      = function() OnOK() end },
        { kind = "textfield", controlName = "RetypeNewPasswordEditBox",
          textKey       = "TXT_KEY_MP_RETYPE_PASSWORD",
          priorCallback = Validate,
          commitFn      = function() OnOK() end },
        { kind = "button",   controlName = "OKButton",
          textKey  = "TXT_KEY_OK_BUTTON",
          activate = function() OnOK() end },
        { kind = "button",   controlName = "CancelButton",
          textKey  = "TXT_KEY_CANCEL_BUTTON",
          activate = function() OnCancel() end },
    },
})
