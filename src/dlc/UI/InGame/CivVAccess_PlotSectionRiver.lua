-- River edges section. Civ V stores rivers per hex edge but only on three
-- of a plot's six edges (W, NW, NE). The opposite three (E, SE, SW) live
-- on the W / NW / NE flag of the plot's E / SE / SW neighbor respectively.
-- We assemble all six edges and announce them in a fixed clockwise order
-- starting from NE so the same river always reads the same way regardless
-- of cursor approach. Six-of-six collapses to a single "river all sides"
-- token so the user doesn't sit through six direction tokens for what is
-- effectively "you are on a river island."

local SELF_EDGES = {
    { dir = "TXT_KEY_CIVVACCESS_DIR_NE", method = "IsNEOfRiver" },
    { dir = "TXT_KEY_CIVVACCESS_DIR_W",  method = "IsWOfRiver"  },
    { dir = "TXT_KEY_CIVVACCESS_DIR_NW", method = "IsNWOfRiver" },
}

-- (neighbor direction, method on neighbor returning true if THAT edge of
-- ours is a river). The neighbor's W flag is our E edge, etc.
local NEIGHBOR_EDGES = {
    { dir = "TXT_KEY_CIVVACCESS_DIR_E",
      neighborDir = "DIRECTION_EAST",      method = "IsWOfRiver"  },
    { dir = "TXT_KEY_CIVVACCESS_DIR_SE",
      neighborDir = "DIRECTION_SOUTHEAST", method = "IsNWOfRiver" },
    { dir = "TXT_KEY_CIVVACCESS_DIR_SW",
      neighborDir = "DIRECTION_SOUTHWEST", method = "IsNEOfRiver" },
}

-- Spoken order (clockwise from NE), independent of how we collected the
-- edges above. Keep this list as the single source of truth for output
-- ordering -- the river-all-sides collapse depends on the count matching
-- this list's length.
local SPOKEN_ORDER = {
    "TXT_KEY_CIVVACCESS_DIR_NE",
    "TXT_KEY_CIVVACCESS_DIR_E",
    "TXT_KEY_CIVVACCESS_DIR_SE",
    "TXT_KEY_CIVVACCESS_DIR_SW",
    "TXT_KEY_CIVVACCESS_DIR_W",
    "TXT_KEY_CIVVACCESS_DIR_NW",
}

PlotSectionRiver = {
    Read = function(plot)
        local edges = {}
        for _, e in ipairs(SELF_EDGES) do
            if plot[e.method](plot) then edges[e.dir] = true end
        end
        for _, e in ipairs(NEIGHBOR_EDGES) do
            local n = Map.PlotDirection(plot:GetX(), plot:GetY(),
                DirectionTypes[e.neighborDir])
            if n ~= nil and n[e.method](n) then edges[e.dir] = true end
        end

        local present = {}
        for _, dir in ipairs(SPOKEN_ORDER) do
            if edges[dir] then present[#present + 1] = Text.key(dir) end
        end

        if #present == 0 then return {} end
        if #present == #SPOKEN_ORDER then
            return { Text.key("TXT_KEY_CIVVACCESS_RIVER_ALL_SIDES") }
        end
        return { Text.key("TXT_KEY_CIVVACCESS_RIVER_PREFIX")
                  .. " " .. table.concat(present, " ") }
    end,
}
