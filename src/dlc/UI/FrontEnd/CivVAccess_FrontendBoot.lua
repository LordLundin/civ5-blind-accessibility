-- Front-end boot. Runs once per front-end Context instantiation via the
-- ToolTips.lua override.
civvaccess_shared = civvaccess_shared or {}
include("CivVAccess_FrontEndStrings_en_US")
print("[CivVAccess] FrontendBoot: ToolTips override fired")

if not civvaccess_shared.frontendAnnounced then
    civvaccess_shared.frontendAnnounced = true
    local text = (CivVAccess_Strings and CivVAccess_Strings["TXT_KEY_CIVVACCESS_BOOT_FRONTEND"])
        or "TXT_KEY_CIVVACCESS_BOOT_FRONTEND"
    print("[CivVAccess] FrontendBoot: announce=" .. tostring(text))
    if tolk ~= nil and tolk.output ~= nil then
        tolk.output(text, true)
    end
end
