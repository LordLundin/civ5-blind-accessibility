-- Select Map Type accessibility wiring.
-- The base screen is a folder tree: Refresh() builds a rootFolder with
-- nested sub-folders, View(folder) renders folder.Items. Our items are
-- kept in sync by wrapping the global View: after the base renders, we
-- translate folder.Items into Choice items. Sub-folder entries drill in
-- via their own Callback (= View(subfolder)); folder.ParentFolder handles
-- back navigation. Leaf entries call through to OnMapScriptSelected /
-- OnMultiSizeMapSelected (via v.Callback), which fires OnBack and pops
-- our handler through the Context's ShowHide.

include("CivVAccess_FrontendCommon")

local priorShowHide = ShowHideHandler
local priorInput    = InputHandler
local handler

-- Map-type entries: supported-size suffix -------------------------------
--
-- Same three shapes as AdvancedSetupAccess's MapTypePullDown:
--   * Pure map scripts (Lua generators) -- work at every world size.
--   * Maps() rows -- constrained by Map_Sizes rows keyed to the row's
--     MapType.
--   * Loose WB map files not referenced by any Map_Sizes row -- pinned
--     to the single world size embedded in wb.MapSize.
--
-- Base here builds a folder tree rather than a pulldown, so positional
-- matching (as in Advanced) won't work. Instead we index by localized
-- name and look up when rendering each leaf. Name collisions between a
-- Maps() row and a loose WB map are avoided by base's filter: loose WB
-- maps whose filenames appear in Map_Sizes are excluded.

local _sizeByNameCache

local function worldNameById(worldID)
    local w = GameInfo.Worlds[worldID]
    if w == nil then return nil end
    return Text.key(w.Description)
end

local function worldNameByType(typeKey)
    local w = GameInfo.Worlds[typeKey]
    if w == nil then return nil end
    return Text.key(w.Description)
end

local function buildSizeByName()
    local total
    do
        local n = 0
        for _ in GameInfo.Worlds("ID >= 0") do n = n + 1 end
        total = n
    end

    local function formatSuffix(sizes)
        if #sizes == 0 or #sizes == total then return nil end
        if #sizes == 1 then
            return Text.format("TXT_KEY_CIVVACCESS_MAP_SIZE_ONLY",
                sizes[1])
        end
        return Text.format("TXT_KEY_CIVVACCESS_MAP_SIZE_LIMITED",
            table.concat(sizes, ", "))
    end

    local byName = {}
    for row in GameInfo.Maps() do
        local sizes = {}
        for srow in GameInfo.Map_Sizes{MapType = row.Type} do
            local s = worldNameByType(srow.WorldSizeType)
            if s ~= nil then sizes[#sizes + 1] = s end
        end
        local suffix = formatSuffix(sizes)
        if suffix ~= nil then
            byName[Locale.Lookup(row.Name)] = suffix
        end
    end

    local filter = {}
    for row in GameInfo.Map_Sizes() do
        filter[Path.GetFileName(row.FileName)] = true
    end
    for _, map in ipairs(Modding.GetMapFiles()) do
        if not filter[Path.GetFileName(map.File)] then
            local wb = UI.GetMapPreview(map.File)
            local name
            if map.Name and not Locale.IsNilOrWhitespace(map.Name) then
                name = map.Name
            elseif wb ~= nil and not Locale.IsNilOrWhitespace(wb.Name) then
                name = Locale.Lookup(wb.Name)
            else
                name = Path.GetFileNameWithoutExtension(map.File)
            end
            if wb ~= nil and wb.MapSize ~= nil then
                local s = worldNameById(wb.MapSize)
                if s ~= nil then
                    byName[name] = Text.format(
                        "TXT_KEY_CIVVACCESS_MAP_SIZE_ONLY", s)
                end
            end
        end
    end
    return byName
end

local function sizeByName()
    if _sizeByNameCache == nil then
        _sizeByNameCache = buildSizeByName()
    end
    return _sizeByNameCache
end

-- Localized name of the currently selected map script, if PreGame's
-- current script resolves to a known row. Used to point the cursor at
-- the current selection when the screen opens.
local function currentSelectionName()
    if PreGame.IsRandomMapScript() then
        return Text.key("TXT_KEY_RANDOM_MAP_SCRIPT")
    end
    local file = PreGame.GetMapScript()
    for row in GameInfo.MapScripts{FileName = file} do
        return Text.key(row.Name)
    end
    for row in GameInfo.Map_Sizes{FileName = file} do
        local entry = GameInfo.Maps[row.MapType]
        if entry ~= nil then return Text.key(entry.Name) end
    end
end

-- Returns (items[], index-of-current-selection or nil).
local function buildItemsForFolder(folder)
    local items = {}
    local selectedIdx = nil
    local selectionName = currentSelectionName()
    if folder.ParentFolder ~= nil then
        local parent = folder.ParentFolder
        items[#items + 1] = BaseMenuItems.Choice({
            labelText  = Text.key("TXT_KEY_SELECT_MAP_TYPE_BACK"),
            tooltipKey = "TXT_KEY_SELECT_MAP_TYPE_BACK_HELP",
            activate   = function()
                View(parent)
                -- rootFolder has no Name; fall back to the screen display name.
                local label = parent.Name
                if label == nil or label == "" then
                    label = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MAP_TYPE")
                end
                SpeechPipeline.speakInterrupt(label)
            end,
        })
    end
    for _, v in ipairs(folder.Items) do
        -- Mirror base: hide empty folders. Also skip unpickable leaves --
        -- the base renders these in red with no Callback (invalid WB maps
        -- or similar); sighted users see them but cannot click, and for
        -- speech surfacing a silent dead end is worse than omitting.
        local isSubFolder = (v.Items ~= nil)
        local isPickableLeaf = (not isSubFolder) and v.Callback ~= nil
        local isNonEmptyFolder = isSubFolder and #v.Items > 0
        if isPickableLeaf or isNonEmptyFolder then
            local callback = v.Callback
            local name = v.Name
            local desc = v.Description
            local label = name
            if not isSubFolder then
                local suffix = sizeByName()[name]
                if suffix ~= nil and suffix ~= "" then
                    label = name .. ", " .. suffix
                end
            end
            -- Sub-folders are drill-ins with no "selected" concept; only
            -- leaves whose name matches the current PreGame map script
            -- carry a selection flag. Captured at build time because the
            -- commit path closes the screen (HandlerStack.active()
            -- guards the re-announce).
            local isCurrentLeaf = (not isSubFolder)
                and selectionName ~= nil and name == selectionName
            local selectedFn
            if isCurrentLeaf then
                selectedFn = function() return true end
            end
            items[#items + 1] = BaseMenuItems.Choice({
                labelText   = label,
                tooltipText = desc,
                selectedFn  = selectedFn,
                activate    = function()
                    if callback ~= nil then callback() end
                    -- Sub-folder drill-in: announce the folder so the user
                    -- knows they moved. Leaf selection closes the screen via
                    -- OnBack and the parent handler re-announces, so skip.
                    if isSubFolder then
                        SpeechPipeline.speakInterrupt(name)
                    end
                end,
            })
            if isCurrentLeaf then selectedIdx = #items end
        end
    end
    return items, selectedIdx
end

local originalView = View
function View(folder)
    originalView(folder)
    if handler ~= nil then
        local items, selectedIdx = buildItemsForFolder(folder)
        handler.setItems(items)
        -- setInitialIndex only fires through onActivate on the next fresh
        -- open (install's ShowHide clears _initialized on hide). On
        -- drill-in the handler stays active, so reset the cursor directly
        -- so the user isn't left at the old parent-folder index. If the
        -- current pick is in this folder, land on it; otherwise land on
        -- the first real entry (slot 2 when a Back entry exists, else 1).
        handler.setInitialIndex(selectedIdx)
        local hasBack = folder.ParentFolder ~= nil
        handler.setIndex(selectedIdx or (hasBack and 2 or 1))
    end
end

handler = BaseMenu.install(ContextPtr, {
    name          = "SelectMapType",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MAP_TYPE"),
    priorShowHide = priorShowHide,
    priorInput    = priorInput,
    onShow        = function() _sizeByNameCache = nil end,
    items         = {},
})
