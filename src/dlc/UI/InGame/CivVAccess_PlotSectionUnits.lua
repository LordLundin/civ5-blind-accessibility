-- Units section. Walks plot:GetNumUnits() then plot:GetNumLayerUnits(),
-- gating each surviving unit with the standard IsInvisible(activeTeam,
-- isDebug) check. The two lists do not overlap (UnitFlagManager treats
-- them as separate collections); no dedup needed.
--
-- Layer-unit filtering: skip cargo (it's inside a transport that's
-- already announced) and skip air (parked in a city / on a carrier, not
-- "on the tile" in any spatial sense the cursor cares about). Trade
-- caravans / cargo ships are layer units that ARE on the map and get
-- announced.

PlotSectionUnits = {}

local function unitDescription(unit)
    local owner = Players[unit:GetOwner()]
    -- Multiplayer nickname path mirrors PlotMouseoverInclude.GetUnitsString.
    if owner.GetNickName ~= nil then
        local nick = owner:GetNickName()
        if nick ~= nil and nick ~= "" then
            return Text.format("TXT_KEY_MULTIPLAYER_UNIT_TT",
                nick, owner:GetCivilizationAdjectiveKey(), unit:GetNameKey())
        end
    end
    if unit:HasName() then
        local desc = Text.format("TXT_KEY_PLOTROLL_UNIT_DESCRIPTION_CIV",
            owner:GetCivilizationAdjectiveKey(), unit:GetNameKey())
        return Text.key(unit:GetNameNoDesc()) .. " (" .. desc .. ")"
    end
    return Text.format("TXT_KEY_PLOTROLL_UNIT_DESCRIPTION_CIV",
        owner:GetCivilizationAdjectiveKey(), unit:GetNameKey())
end

local function describeUnit(unit, activeTeam, isDebug)
    if unit:IsInvisible(activeTeam, isDebug) then return nil end
    local s = unitDescription(unit)
    local damage = unit:GetDamage()
    if damage > 0 then
        s = s .. ", " .. Text.format("TXT_KEY_CIVVACCESS_HP_FORMAT",
            GameDefines.MAX_HIT_POINTS - damage)
    end
    return s
end

PlotSectionUnits.section = {
    Read = function(plot)
        local team    = Game.GetActiveTeam()
        local isDebug = Game.IsDebugMode()
        local out = {}

        local n = plot:GetNumUnits()
        for i = 0, n - 1 do
            local u = plot:GetUnit(i)
            if u ~= nil then
                local desc = describeUnit(u, team, isDebug)
                if desc ~= nil then out[#out + 1] = desc end
            end
        end

        local m = plot:GetNumLayerUnits()
        for i = 0, m - 1 do
            local u = plot:GetLayerUnit(i)
            if u ~= nil and not u:IsCargo()
                    and u:GetDomainType() ~= DomainTypes.DOMAIN_AIR then
                local desc = describeUnit(u, team, isDebug)
                if desc ~= nil then out[#out + 1] = desc end
            end
        end

        return out
    end,
}
