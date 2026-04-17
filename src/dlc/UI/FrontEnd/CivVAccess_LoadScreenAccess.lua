-- LoadScreen accessibility wiring. The map-generation splash between map
-- launch and first turn. The engine narrates the Dawn of Man quote audibly,
-- so we stay silent on entry and don't install a handler (no navigable
-- controls while loading). The base InputHandler already routes Enter and
-- Esc to OnActivateButtonClicked once g_bLoadComplete is true, so all we
-- need is a speech cue that input is now accepted.
--
-- MP / hotseat games auto-activate via OnSequenceGameInitComplete without
-- user input; skip the cue in those cases since there is nothing to press.
--
-- Idempotency: Events.SequenceGameInitComplete is a session-wide bus; guard
-- on civvaccess_shared so repeated Context instantiation doesn't double up
-- listeners.

include("CivVAccess_FrontendCommon")

if not civvaccess_shared.loadScreenReadyListenerInstalled then
    civvaccess_shared.loadScreenReadyListenerInstalled = true
    Events.SequenceGameInitComplete.Add(function()
        if PreGame.IsMultiplayerGame() or PreGame.IsHotSeatGame() then return end
        SpeechPipeline.speakInterrupt(Text.key("TXT_KEY_CIVVACCESS_LOAD_READY"))
    end)
end
