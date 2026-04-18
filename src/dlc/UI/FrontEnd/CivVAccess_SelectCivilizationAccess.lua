-- Select Civilization accessibility wiring.
-- Modal popup, opened via UIManager:QueuePopup from the parent screen.
-- Items rebuild on every show because DLC activation and scenario toggle
-- both reshape the playable-civ set; the base file gates its InstanceManager
-- rebuild on g_bRefreshCivs / WB map, but rebuilding our items every show
-- is cheap and removes the dependency on those flags.

include("CivVAccess_FrontendCommon")
include("CivVAccess_CivDetails")

-- Parallel to the last-built items[]: civIds[i] is the civID committed by
-- items[i]:activate (or -1 for Random / no civ). Rebuilt on every show
-- alongside items so currentIndex can map PreGame.GetCivilization back to
-- a slot. Unlike the other Select* screens' caches this is regenerated
-- inside rebuildItems on every show, not carried across shows.
local civIds = {}

local function currentIndex()
    local current = PreGame.GetCivilization(0)
    for i, id in ipairs(civIds) do
        if id == current then return i end
    end
end

local function buildRegularItems()
    civIds = { -1 }
    local items = {
        BaseMenuItems.Choice({
            labelText   = Text.key("TXT_KEY_RANDOM_LEADER") .. ", "
                        .. Text.key("TXT_KEY_RANDOM_CIV"),
            tooltipText = Text.key("TXT_KEY_RANDOM_LEADER_HELP"),
            selectedFn  = function() return PreGame.GetCivilization(0) == -1 end,
            activate    = function() CivilizationSelected(-1) end,
        }),
    }
    local entries = {}
    local sql = [[SELECT
        Civilizations.ID,
        Civilizations.Type,
        Civilizations.ShortDescription,
        Leaders.Type AS LeaderType,
        Leaders.Description AS LeaderDescription
        FROM Civilizations, Leaders, Civilization_Leaders WHERE
        Civilizations.Type = Civilization_Leaders.CivilizationType AND
        Leaders.Type = Civilization_Leaders.LeaderheadType AND
        Civilizations.Playable = 1]]
    for row in DB.Query(sql) do
        entries[#entries + 1] = { Text.key(row.LeaderDescription), row }
    end
    table.sort(entries, function(a, b) return Locale.Compare(a[1], b[1]) == -1 end)
    for _, entry in ipairs(entries) do
        local row   = entry[2]
        local civID = row.ID
        civIds[#civIds + 1] = civID
        items[#items + 1] = BaseMenuItems.Choice({
            labelText  = CivDetails.richLabel(row),
            selectedFn = function() return PreGame.GetCivilization(0) == civID end,
            activate   = function() CivilizationSelected(civID) end,
        })
    end
    return items
end

local function buildScenarioItems()
    civIds = {}
    local items = {}
    local civList = UI.GetMapPlayers(PreGame.GetMapScript())
    if civList == nil then return items end
    local query = DB.CreateQuery([[SELECT
        Civilizations.ID,
        Civilizations.Type,
        Civilizations.ShortDescription,
        Leaders.Type AS LeaderType,
        Leaders.Description AS LeaderDescription
        FROM Civilizations, Leaders, Civilization_Leaders WHERE
        Civilizations.ID = ? AND
        Civilizations.Type = Civilization_Leaders.CivilizationType AND
        Leaders.Type = Civilization_Leaders.LeaderheadType LIMIT 1]])
    local entries = {}
    for i, v in pairs(civList) do
        if v.Playable then
            for row in query(v.CivType) do
                entries[#entries + 1] = {
                    Text.key(row.LeaderDescription), row, i - 1,
                }
            end
        end
    end
    table.sort(entries, function(a, b) return Locale.Compare(a[1], b[1]) == -1 end)
    for _, entry in ipairs(entries) do
        local row            = entry[2]
        local scenarioCivID  = entry[3]
        local civID          = row.ID
        civIds[#civIds + 1]  = civID
        items[#items + 1] = BaseMenuItems.Choice({
            labelText  = CivDetails.richLabel(row),
            -- Base's currentIndex checks PreGame.GetCivilization(0)
            -- unconditionally, so we mirror that. Scenario slot targeting
            -- is only used by activate (for the SetCivilization write);
            -- the "which is currently set" read is always slot 0.
            selectedFn = function() return PreGame.GetCivilization(0) == civID end,
            activate   = function()
                CivilizationSelected(civID, scenarioCivID)
            end,
        })
    end
    return items
end

local function rebuildItems(h)
    local items
    if PreGame.GetLoadWBScenario() and IsWBMap(PreGame.GetMapScript()) then
        items = buildScenarioItems()
    else
        items = buildRegularItems()
    end
    if h ~= nil then h.setItems(items) end
    return items
end

BaseMenu.install(ContextPtr, {
    name          = "SelectCivilization",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_CIVILIZATION"),
    priorShowHide = ShowHideHandler,
    priorInput    = InputHandler,
    onShow        = function(h)
        rebuildItems(h)
        h.setInitialIndex(currentIndex())
    end,
    items         = rebuildItems(nil),
})
