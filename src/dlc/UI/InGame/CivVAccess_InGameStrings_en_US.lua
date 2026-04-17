-- Mod-authored localized strings, in-game Context.
-- Looked up by Text.key / Text.format in CivVAccess_Text.lua. Sets a global
-- (rather than returning) so the offline test harness can dofile() it without
-- relying on Civ V's include() semantics.
CivVAccess_Strings = CivVAccess_Strings or {}
CivVAccess_Strings["TXT_KEY_CIVVACCESS_BOOT_INGAME"]       = "Civilization V accessibility loaded in-game."
CivVAccess_Strings["TXT_KEY_CIVVACCESS_BUTTON_DISABLED"]   = "disabled"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEXTFIELD_EDIT"]      = "edit"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEXTFIELD_BLANK"]     = "blank"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEXTFIELD_EDITING"]   = "editing {1_Label}"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEXTFIELD_RESTORED"]  = "{1_Label} restored"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_TEXTFIELD_COMMITTED"] = "{1_Label} committed"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_SCREEN_SET_CITY_NAME"] = "Rename city"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_SCREEN_SET_UNIT_NAME"] = "Rename unit"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_SCREEN_CHANGE_PASSWORD"] = "Change password"
CivVAccess_Strings["TXT_KEY_CIVVACCESS_SCREEN_SAVE_MENU"]    = "Save game"
