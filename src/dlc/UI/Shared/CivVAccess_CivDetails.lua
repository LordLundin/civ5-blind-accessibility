-- Shared rich civ-label builder. Used by SelectCivilization's picker and
-- AdvancedSetup's civ pulldown so both screens produce the same detail:
-- leader, civ short name, unique ability (name + description), unique
-- unit, unique building, unique improvement. Keeps the two screens from
-- drifting.
--
-- The queries are DB.CreateQuery'd at module load so they're prepared
-- once per Context sandbox and reused for each civ-row lookup.

CivDetails = {}

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

local uniqueImprovementsQuery = DB.CreateQuery([[SELECT Description FROM Improvements WHERE CivilizationType = ?]])

local traitsQuery = DB.CreateQuery([[SELECT Description, ShortDescription FROM Traits
    INNER JOIN Leader_Traits ON Traits.Type = Leader_Traits.TraitType
    WHERE Leader_Traits.LeaderType = ? LIMIT 1]])

local function appendLabeled(parts, labelKey, value)
    if value == nil or value == "" then
        return
    end
    parts[#parts + 1] = Text.key(labelKey) .. ": " .. value
end

-- `row` must carry LeaderDescription, ShortDescription, Type, LeaderType.
-- Returns a ", "-joined string with each piece prefix-labeled where the
-- prefix helps distinguish the value (Unique ability: X, ...). Civ /
-- leader names don't get prefixes because the surrounding context makes
-- them obvious.
function CivDetails.richLabel(row)
    local parts = {
        Text.key(row.LeaderDescription),
        Text.key(row.ShortDescription),
    }
    for t in traitsQuery(row.LeaderType) do
        local name = Text.key(t.ShortDescription)
        local desc = Text.key(t.Description)
        if name ~= nil and name ~= "" then
            local value = name
            if desc ~= nil and desc ~= "" then
                value = value .. ", " .. desc
            end
            parts[#parts + 1] = Text.key("TXT_KEY_CIVVACCESS_UNIQUE_ABILITY") .. ": " .. value
        end
    end
    for urow in uniqueUnitsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_UNIT", Text.key(urow.Description))
    end
    for urow in uniqueBuildingsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_BUILDING", Text.key(urow.Description))
    end
    for urow in uniqueImprovementsQuery(row.Type) do
        appendLabeled(parts, "TXT_KEY_CIVVACCESS_UNIQUE_IMPROVEMENT", Text.key(urow.Description))
    end
    return table.concat(parts, ", ")
end

-- Returns the pulldown-ordered label list used by AdvancedSetup's civ
-- pulldown (both the human's and each per-slot one). Index 1 is the
-- "random" entry base builds first; indices 2..N+1 are the playable
-- civilizations sorted by leader description, matching the order base's
-- Civs.FullSync feeds BuildEntry.
function CivDetails.pulldownLabels()
    local labels = {
        Text.key("TXT_KEY_RANDOM_LEADER") .. ", " .. Text.key("TXT_KEY_RANDOM_CIV"),
    }
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
    local entries = {}
    for row in DB.Query(sql) do
        entries[#entries + 1] = { Text.key(row.LeaderDescription), row }
    end
    table.sort(entries, function(a, b)
        return Locale.Compare(a[1], b[1]) == -1
    end)
    for _, entry in ipairs(entries) do
        labels[#labels + 1] = CivDetails.richLabel(entry[2])
    end
    return labels
end

return CivDetails
