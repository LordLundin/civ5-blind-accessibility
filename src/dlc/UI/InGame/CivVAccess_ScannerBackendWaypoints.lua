-- Scanner backend: queued-move waypoints for the active selected unit.
-- One entry per plot the unit will step onto across its mission queue,
-- numbered start-to-end. Source of truth is WaypointsCore (cached by
-- selection / queue signature); this file is just the scanner shape.
--
-- Multiple waypoints can land on the same plot (a queue with reversal
-- legs walks the same plot twice). Each gets its own scanner entry with
-- a unique key so identity-preserving rebuild doesn't collapse them.

ScannerBackendWaypoints = {
    name = "waypoints",
}

function ScannerBackendWaypoints.Scan(_activePlayer, _activeTeam)
    local out = {}
    local list = Waypoints.list()
    for i, wp in ipairs(list) do
        local plot = Map.GetPlot(wp.x, wp.y)
        if plot ~= nil then
            local plotIdx = plot:GetPlotIndex()
            out[#out + 1] = {
                plotIndex = plotIdx,
                backend = ScannerBackendWaypoints,
                data = { index = i },
                category = "waypoints",
                subcategory = "all",
                itemName = Text.format("TXT_KEY_CIVVACCESS_PLOT_WAYPOINT", i, #list),
                key = "waypoints:" .. plotIdx .. ":" .. i,
                sortKey = i,
            }
        end
    end
    return out
end

-- Re-resolve against a fresh waypoint list. Membership rather than just
-- index-position because shift+queueing or a unit completing its current
-- leg changes the numbering, and an entry whose stored index falls out
-- of the new list (or whose plot no longer matches that index) must
-- drop rather than mis-announce a stale waypoint number.
function ScannerBackendWaypoints.ValidateEntry(entry, _cursorPlotIndex)
    local plot = Map.GetPlotByIndex(entry.plotIndex)
    if plot == nil then
        return false
    end
    local list = Waypoints.list()
    local idx = entry.data.index
    local wp = list[idx]
    if wp == nil then
        return false
    end
    return wp.x == plot:GetX() and wp.y == plot:GetY()
end

function ScannerBackendWaypoints.FormatName(entry)
    return entry.itemName
end

ScannerCore.registerBackend(ScannerBackendWaypoints)
