-- DiploGlobalRelationships accessibility. The Global Politics tab of
-- DiploOverview; lists major civs with era, war-with-us / we-denounced
-- flags, policy counts per branch, wonders owned, and a third-party
-- strip (civs at war with each other, DoFs, denunciations, CS alliances).
-- Activation opens AI trade / PvP trade, matching base LeaderSelected.
--
-- Tab / Shift+Tab cycle to sibling tabs (Relations / Deals); see
-- CivVAccess_DiploOverviewBridge for the cross-Context mechanism.

include("CivVAccess_Polyfill")
include("CivVAccess_Log")
include("CivVAccess_TextFilter")
include("CivVAccess_InGameStrings_en_US")
include("CivVAccess_Text")
include("CivVAccess_Icons")
include("CivVAccess_SpeechEngine")
include("CivVAccess_SpeechPipeline")
include("CivVAccess_HandlerStack")
include("CivVAccess_InputRouter")
include("CivVAccess_TickPump")
include("CivVAccess_Nav")
include("CivVAccess_BaseMenuItems")
include("CivVAccess_TypeAheadSearch")
include("CivVAccess_BaseMenuHelp")
include("CivVAccess_BaseMenuTabs")
include("CivVAccess_BaseMenuCore")
include("CivVAccess_BaseMenuInstall")
include("CivVAccess_Help")

local function joinParts(parts)
    local out = {}
    for _, p in ipairs(parts) do
        if p ~= nil and p ~= "" then
            out[#out + 1] = tostring(p)
        end
    end
    return table.concat(out, ", ")
end

-- Return the display name for a third-party player that respects
-- "nickname for humans, civ short description for AI, TXT_KEY_YOU for
-- the active player" -- matching the base code's third-party branches.
local function thirdPartyName(iThird, iUs)
    if iThird == iUs then
        return Text.key("TXT_KEY_YOU")
    end
    local p = Players[iThird]
    if p:IsHuman() then
        return p:GetNickName()
    end
    return Locale.ConvertTextKey(p:GetCivilizationShortDescription())
end

-- Policies per branch with non-zero count. Matches base's per-branch
-- iteration; formatted as "Tradition 4".
local function policyFragment(pOther)
    local out = {}
    for branch in GameInfo.PolicyBranchTypes() do
        local count = 0
        for policy in GameInfo.Policies() do
            if policy.PolicyBranchType == branch.Type and pOther:HasPolicy(policy.ID) then
                count = count + 1
            end
        end
        if count > 0 then
            local branchName = Locale.ConvertTextKey(branch.Description)
            out[#out + 1] = Text.format("TXT_KEY_CIVVACCESS_DIPLO_POLICY_COUNT", branchName, tostring(count))
        end
    end
    if #out == 0 then
        return nil
    end
    return Text.format("TXT_KEY_CIVVACCESS_DIPLO_POLICIES_LIST", table.concat(out, ", "))
end

-- Wonders the other civ has built. Wonder = BuildingClass with
-- MaxGlobalInstances > 0, owned by the civ.
local function wondersFragment(pOther)
    local names = {}
    for building in GameInfo.Buildings() do
        local bc = GameInfo.BuildingClasses[building.BuildingClass]
        if bc.MaxGlobalInstances > 0 and pOther:CountNumBuildings(building.ID) > 0 then
            names[#names + 1] = Locale.ConvertTextKey(building.Description)
        end
    end
    if #names == 0 then
        return nil
    end
    return Text.format("TXT_KEY_CIVVACCESS_DIPLO_WONDERS_LIST", table.concat(names, ", "))
end

-- Third-party relationship fragments: war, DoF, denounce, CS alliance.
-- Returns a flat list of strings, already formatted.
local function thirdPartyFragments(iUs, iOther, pUsTeam, pOtherTeam, pOther)
    local frags = {}

    -- Wars between pOther and other majors (excluding us -- at-war-with-us
    -- is handled in the header's "at war" flag).
    for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
        if i ~= iOther and i ~= iUs then
            local pThird = Players[i]
            if pThird ~= nil and pThird:IsAlive() then
                local iThirdTeam = pThird:GetTeam()
                if pUsTeam:IsHasMet(iThirdTeam) and pOtherTeam:IsAtWar(iThirdTeam) then
                    frags[#frags + 1] = Locale.ConvertTextKey("TXT_KEY_AT_WAR_WITH", thirdPartyName(i, iUs))
                end
            end
        end
    end

    -- Declarations of Friendship between pOther and anyone (including us).
    for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
        if i ~= iOther then
            local pThird = Players[i]
            if pThird ~= nil and pThird:IsAlive() then
                local iThirdTeam = pThird:GetTeam()
                if (pUsTeam:IsHasMet(iThirdTeam) or i == iUs) and pOther:IsDoF(i) then
                    frags[#frags + 1] = Locale.ConvertTextKey("TXT_KEY_DIPLO_FRIENDS_WITH", thirdPartyName(i, iUs))
                end
            end
        end
    end

    -- Denunciations from pOther toward anyone.
    for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
        if i ~= iOther then
            local pThird = Players[i]
            if pThird ~= nil and pThird:IsAlive() then
                local iThirdTeam = pThird:GetTeam()
                if pUsTeam:IsHasMet(iThirdTeam) or i == iUs then
                    if pOther:IsDenouncedPlayer(i) or pThird:IsFriendDeclaredWarOnUs(iOther) then
                        local name = thirdPartyName(i, iUs)
                        if pThird:IsFriendDenouncedUs(iOther) or pThird:IsFriendDeclaredWarOnUs(iOther) then
                            frags[#frags + 1] = Locale.ConvertTextKey("TXT_KEY_DIPLO_BACKSTABBED", name)
                        else
                            frags[#frags + 1] = Locale.ConvertTextKey("TXT_KEY_DIPLO_DENOUNCED", name)
                        end
                    end
                end
            end
        end
    end

    -- City-state alliances with pOther.
    for i = GameDefines.MAX_MAJOR_CIVS, GameDefines.MAX_CIV_PLAYERS - 1 do
        local pThird = Players[i]
        if pThird ~= nil and pThird:IsAlive() then
            local iThirdTeam = pThird:GetTeam()
            if (pUsTeam:IsHasMet(iThirdTeam) or i == iUs) and pThird:IsAllies(iOther) then
                local csName = Locale.ConvertTextKey(pThird:GetCivilizationShortDescription())
                frags[#frags + 1] = Locale.ConvertTextKey("TXT_KEY_ALLIED_WITH", csName)
            end
        end
    end

    return frags
end

local function majorCivItem(iUs, pUs, pUsTeam, iOther)
    local pOther = Players[iOther]
    local pOtherTeam = Teams[pOther:GetTeam()]
    local civName = Locale.ConvertTextKey(GameInfo.Civilizations[pOther:GetCivilizationType()].ShortDescription)
    local leaderName = pOther:GetName()
    local nameLine = Text.format("TXT_KEY_CIVVACCESS_DIPLO_LEADER_OF_CIV", leaderName, civName)
    local era = Locale.ConvertTextKey(GameInfo.Eras[pOther:GetCurrentEra()].Description)

    local parts = { nameLine, era }

    if pUsTeam:IsAtWar(pOther:GetTeam()) then
        parts[#parts + 1] = Locale.ConvertTextKey("TXT_KEY_DO_AT_WAR")
    end

    if pUs:IsDenouncedPlayer(iOther) then
        if pOther:IsFriendDenouncedUs(iUs) or pOther:IsFriendDeclaredWarOnUs(iUs) then
            parts[#parts + 1] = Text.key("TXT_KEY_DIPLO_YOU_HAVE_BACKSTABBED")
        else
            parts[#parts + 1] = Text.key("TXT_KEY_DIPLO_YOU_HAVE_DENOUNCED")
        end
    end

    local policies = policyFragment(pOther)
    if policies then
        parts[#parts + 1] = policies
    end

    local wonders = wondersFragment(pOther)
    if wonders then
        parts[#parts + 1] = wonders
    end

    for _, f in ipairs(thirdPartyFragments(iUs, iOther, pUsTeam, pOtherTeam, pOther)) do
        parts[#parts + 1] = f
    end

    local label = joinParts(parts)
    local capturedOther = iOther
    return BaseMenuItems.Choice({
        labelText = label,
        activate = function()
            if Players[capturedOther]:IsHuman() then
                Events.OpenPlayerDealScreenEvent(capturedOther)
            else
                UI.SetRepeatActionPlayer(capturedOther)
                UI.ChangeStartDiploRepeatCount(1)
                Players[capturedOther]:DoBeginDiploWithHuman()
            end
        end,
    })
end

local function buildItems()
    local iUs = Game.GetActivePlayer()
    local pUs = Players[iUs]
    local pUsTeam = Teams[pUs:GetTeam()]
    local items = {}
    for i = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
        local pOther = Players[i]
        if i ~= iUs and pOther:IsAlive() and pUsTeam:IsHasMet(pOther:GetTeam()) then
            items[#items + 1] = majorCivItem(iUs, pUs, pUsTeam, i)
        end
    end
    return items
end

local function onTab()
    local bridge = civvaccess_shared.DiploOverview
    if bridge ~= nil and type(bridge.showRelations) == "function" then
        bridge.showRelations()
    end
end
local function onShiftTab()
    local bridge = civvaccess_shared.DiploOverview
    if bridge ~= nil and type(bridge.showDeals) == "function" then
        bridge.showDeals()
    end
end

BaseMenu.install(ContextPtr, {
    name = "DiploGlobalRelationships",
    displayName = Text.key("TXT_KEY_DO_GLOBAL_RELATIONS"),
    priorInput = InputHandler,
    priorShowHide = ShowHideHandler,
    onShow = function(h)
        h.setItems(buildItems())
    end,
    onTab = onTab,
    onShiftTab = onShiftTab,
    items = {},
})
