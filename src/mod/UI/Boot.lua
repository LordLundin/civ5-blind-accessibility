include("CivVAccess_Polyfill")
include("CivVAccess_Log")
include("CivVAccess_TextFilter")
include("CivVAccess_Text")
include("CivVAccess_SpeechEngine")
include("CivVAccess_SpeechPipeline")
include("CivVAccess_HandlerStack")
include("CivVAccess_InputRouter")
include("CivVAccess_TickPump")
include("CivVAccess_BaselineHandler")

-- Boot.lua fires any time a new InGameUIAddin Context loads, which includes
-- front-end activation (via Modding.ActivateEnabledMods) and the pre-game
-- setup flow, not just a real loaded game. Civ V runs the entire session on
-- one lua_State, so there's no state-level discriminator. Events.LoadScreenClose
-- is the reliable "we are actually in a game now" signal; defer the in-game
-- boot actions to it.
local function onInGameBoot()
    Log.info("in-game boot")
    HandlerStack.removeByName("Baseline")
    HandlerStack.push(BaselineHandler.create())
    TickPump.install(ContextPtr)
    -- Mod's TXT_KEY table isn't ingested when Modding.ActivateEnabledMods()
    -- runs via the proxy (that path enables the mod without the normal
    -- game-setup mod-ingestion flow), so Locale.ConvertTextKey returns the
    -- raw key here. Use a mod-authored literal until Session A followups
    -- address mod-ingestion. Matches the front-end announce pattern.
    SpeechPipeline.speakInterrupt("Civilization V accessibility loaded in-game.")
end

if Events ~= nil and Events.LoadScreenClose ~= nil then
    -- Guard against multiple InGameUIAddin contexts each registering a listener
    -- within the same lua_State; civvaccess_shared persists across contexts.
    if not civvaccess_shared.ingameListenerInstalled then
        civvaccess_shared.ingameListenerInstalled = true
        Events.LoadScreenClose.Add(onInGameBoot)
        Log.info("Boot.lua: registered LoadScreenClose listener")
    end
else
    Log.warn("Boot.lua: Events.LoadScreenClose missing; in-game boot will not fire")
end
