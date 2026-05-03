-- WaitingForPlayers accessibility wiring. Status splash the engine shows
-- during load while one or more players haven't finished. In MP / hotseat
-- announce the status; in SP the engine still flashes this screen briefly
-- even though there is no peer to wait on, so skip the announce (LoadScreen
-- handles the SP load cue).
--
-- WaitingForPlayers is a passive status screen with no user interaction, so
-- it doesn't need BaseMenu's navigation layer. Just hook ShowHide to announce
-- when the screen appears, avoiding the context isolation issues that arise
-- from pushing a BaseMenu handler (created in FrontEnd context) onto the
-- shared stack that's accessed from InGame context (WorldView).

include("CivVAccess_FrontendCommon")

local priorShowHide = ShowHide

ContextPtr:SetShowHideHandler(function(isHide)
    priorShowHide(isHide)
    if not isHide and (PreGame.IsMultiplayerGame() or PreGame.IsHotSeatGame()) then
        SpeechPipeline.announce(Text.key("TXT_KEY_SOMEONE_STILL_LOADING"))
    end
end)
