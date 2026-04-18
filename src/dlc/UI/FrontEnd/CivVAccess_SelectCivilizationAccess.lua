-- Select Civilization accessibility wiring.
-- Modal popup, opened via UIManager:QueuePopup from the parent screen.
-- Items rebuild on every show because DLC activation and scenario toggle
-- both reshape the playable-civ set; the base file gates its InstanceManager
-- rebuild on g_bRefreshCivs / WB map, but rebuilding our items every show
-- is cheap and removes the dependency on those flags.

include("CivVAccess_FrontendCommon")

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

-- Each civ announce is: leader, civ short name, then for each non-empty
-- piece a prefix-labeled clause -- "Unique ability: <name>, <description>",
-- "Unique unit: <name>", "Unique building: <name>", "Unique improvement:
-- <name>". Civ name has no prefix (it's obvious from context); everything
-- else does, because a flat run of nouns otherwise sounds like one big
-- list the player has to parse.

local uniqueUnitsQuery = DB.CreateQuery([[SELECT Description FROM Units
    INNER JOIN Civilization_UnitClassOverrides
    ON Units.Type = Civilization_UnitClassOverrides.UnitType
    WHERE Civilization_UnitClassOverrides.CivilizationType = ? AND
    Civilization_UnitClassOverrides.UnitType IS NOT NULL]])

local uniqueBuildingsQuery = DB.CreateQuery([[SELECT Description FROM Buildings
    INNER JOIN Civilization_BuildingClassOverrides
    ON Buildings.Type = Civilization_BuildingClassOverrides.BuildingType
    WHERE Civilization_BuildingClassOverrides.CivilizationType = ? AND
    Civilization_BuildingClassOverrides.BuildingType IS NOT NULL]])

local uniqueImprovementsQuery = DB.CreateQuery(
    [[SELECT Description FROM Improvements WHERE CivilizationType = ?]])

local function appendLabeled(parts, labelKey, value)
    if value == nil or value == "" then return end
    parts[#parts + 1] = Text.key(labelKey) .. ": " .. value
end

-- Appends the shared suffix (ability + uniques) to `parts` for a civ row
-- that has row.Type (civ type) and row.LeaderType. traitsQuery yields
-- {Description, ShortDescription} rows for a leader.
local function appendCivDetails(parts, row, traitsQuery)
    for t in traitsQuery(row.LeaderType) do
        local name = Text.key(t.ShortDescription)
        local desc = Text.key(t.Description)
        if name ~= nil and name ~= "" then
            local value = name
            if desc ~= nil and desc ~= "" then
                value = value .. ", " .. desc
            end
            parts[#parts + 1] = Text.key("TXT_KEY_CIVVACCESS_UNIQUE_ABILITY")
                .. ": " .. value
        end
    end
    for urow in uniqueUnitsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_UNIT",
            Text.key(urow.Description))
    end
    for urow in uniqueBuildingsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_BUILDING",
            Text.key(urow.Description))
    end
    for urow in uniqueImprovementsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_IMPROVEMENT",
            Text.key(urow.Description))
    end
end

local function buildRegularItems(traitsQuery)
    civIds = { -1 }
    local items = {
        BaseMenuItems.Choice({
            labelText   = Text.key("TXT_KEY_RANDOM_LEADER") .. ", "
                        .. Text.key("TXT_KEY_RANDOM_CIV"),
            tooltipText = Text.key("TXT_KEY_RANDOM_LEADER_HELP"),
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
        local row = entry[2]
        local civID = row.ID
        local parts = {
            Text.key(row.LeaderDescription),
            Text.key(row.ShortDescription),
        }
        appendCivDetails(parts, row, traitsQuery)
        civIds[#civIds + 1] = civID
        items[#items + 1] = BaseMenuItems.Choice({
            labelText = table.concat(parts, ", "),
            activate  = function() CivilizationSelected(civID) end,
        })
    end
    return items
end

local function buildScenarioItems(traitsQuery)
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
        local row = entry[2]
        local scenarioCivID = entry[3]
        local civID = row.ID
        local parts = {
            Text.key(row.LeaderDescription),
            Text.key(row.ShortDescription),
        }
        appendCivDetails(parts, row, traitsQuery)
        civIds[#civIds + 1] = civID
        items[#items + 1] = BaseMenuItems.Choice({
            labelText = table.concat(parts, ", "),
            activate  = function()
                CivilizationSelected(civID, scenarioCivID)
            end,
        })
    end
    return items
end

local function rebuildItems(h)
    local traitsQuery = DB.CreateQuery([[SELECT Description, ShortDescription FROM Traits
        INNER JOIN Leader_Traits ON Traits.Type = Leader_Traits.TraitType
        WHERE Leader_Traits.LeaderType = ? LIMIT 1]])
    local items
    if PreGame.GetLoadWBScenario() and IsWBMap(PreGame.GetMapScript()) then
        items = buildScenarioItems(traitsQuery)
    else
        items = buildRegularItems(traitsQuery)
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
