-- Select Map Size accessibility wiring.
-- Items gate on the base file's g_WorldSizeControls[type].Root visibility;
-- the base ShowHideHandler toggles those based on current MapType (via
-- Map_Sizes filtering), so isNavigable picks up only sizes legal for the
-- current script.

include("CivVAccess_FrontendCommon")

local function currentIndex()
    -- items[1] is Random; the rest follow GameInfo.Worlds iteration order,
    -- same order buildItems walks.
    if PreGame.IsRandomWorldSize() then return 1 end
    local current = PreGame.GetWorldSize()
    local i = 1
    for info in GameInfo.Worlds() do
        i = i + 1
        if info.ID == current then return i end
    end
end

local function buildItems()
    local items = {}
    local randomLabel = PreGame.IsMultiplayerGame()
        and "TXT_KEY_ANY_MAP_SIZE" or "TXT_KEY_RANDOM_MAP_SIZE"
    local randomHelp  = PreGame.IsMultiplayerGame()
        and "TXT_KEY_ANY_MAP_SIZE_HELP" or "TXT_KEY_RANDOM_MAP_SIZE_HELP"
    items[#items + 1] = BaseMenuItems.Choice({
        labelText         = Text.key(randomLabel),
        tooltipText       = Text.key(randomHelp),
        visibilityControl = g_RandomSizeControl.Root,
        selectedFn        = function() return PreGame.IsRandomWorldSize() end,
        activate          = function() SizeSelected(-1) end,
    })
    for info in GameInfo.Worlds() do
        local id = info.ID
        local entry = g_WorldSizeControls[info.Type]
        items[#items + 1] = BaseMenuItems.Choice({
            labelText         = Text.key(info.Description),
            tooltipText       = Text.key(info.Help),
            visibilityControl = entry and entry.Root or nil,
            -- PreGame.GetWorldSize can return a stale value while
            -- IsRandomWorldSize is true, so check both to avoid falsely
            -- flagging a specific size as selected under Random.
            selectedFn        = function()
                return not PreGame.IsRandomWorldSize()
                    and PreGame.GetWorldSize() == id
            end,
            activate          = function() SizeSelected(id) end,
        })
    end
    return items
end

BaseMenu.install(ContextPtr, {
    name          = "SelectMapSize",
    displayName   = Text.key("TXT_KEY_CIVVACCESS_SCREEN_MAP_SIZE"),
    priorShowHide = ShowHideHandler,
    priorInput    = InputHandler,
    onShow        = function(h) h.setInitialIndex(currentIndex()) end,
    items         = buildItems(),
})
