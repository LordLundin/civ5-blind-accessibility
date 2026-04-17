-- Include-chain for in-game Contexts other than TaskList (which is where
-- CivVAccess_Boot does the first-time listener registration). Mirror of
-- CivVAccess_FrontendCommon for the in-game skin. Popups that install a
-- FormHandler need Text / SpeechPipeline / HandlerStack / InputRouter in
-- their own sandbox; include() caches by stem so re-running these per
-- Context is cheap.

include("CivVAccess_Polyfill")
include("CivVAccess_Log")
include("CivVAccess_TextFilter")
include("CivVAccess_InGameStrings_en_US")
include("CivVAccess_Text")
include("CivVAccess_SpeechEngine")
include("CivVAccess_SpeechPipeline")
include("CivVAccess_HandlerStack")
include("CivVAccess_InputRouter")
include("CivVAccess_TickPump")
include("CivVAccess_Nav")
