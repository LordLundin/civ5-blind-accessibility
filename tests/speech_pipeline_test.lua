-- SpeechPipeline tests. The pipeline has three seams we substitute:
--   _timeSource   -> controllable clock for dedup window behavior
--   _speakAction  -> capturing sink, records (text, interrupt) tuples
--   SpeechEngine  -> stubbed so stop() is observable without Tolk
-- TextFilter is loaded for real; the pipeline's contract is that it filters
-- before speaking, and we want a filter change to break these tests.

local T = require("support")

Log = {
    debug = function() end, info = function() end,
    warn  = function() end, error = function() end,
}

dofile("src/mod/UI/CivVAccess_TextFilter.lua")

-- Stub SpeechEngine. stop() is observable; say() is unused because we
-- override _speakAction, but we define it for safety against future changes.
local engineStopCount = 0
SpeechEngine = {
    say = function() end,
    stop = function() engineStopCount = engineStopCount + 1 end,
}

dofile("src/mod/UI/CivVAccess_SpeechPipeline.lua")

-- Shared harness state. Each case resets via setup().
local spoken, now
local function setup()
    spoken = {}
    now = 0
    engineStopCount = 0
    SpeechPipeline._timeSource = function() return now end
    SpeechPipeline._speakAction = function(text, interrupt)
        spoken[#spoken + 1] = { text = text, interrupt = interrupt }
    end
    SpeechPipeline._reset()
end

-- Enabled / disabled gate ---------------------------------------------------

T.case("disabled: interrupt is a no-op", function()
    setup()
    SpeechPipeline.setEnabled(false)
    SpeechPipeline.speakInterrupt("hello")
    T.eq(#spoken, 0)
end)

T.case("disabled: queued is a no-op", function()
    setup()
    SpeechPipeline.setEnabled(false)
    SpeechPipeline.speakQueued("hello")
    T.eq(#spoken, 0)
end)

T.case("setEnabled coerces truthy value to true", function()
    setup()
    SpeechPipeline.setEnabled("yes")
    T.truthy(SpeechPipeline.isActive())
end)

T.case("setEnabled coerces nil to false", function()
    setup()
    SpeechPipeline.setEnabled(nil)
    T.falsy(SpeechPipeline.isActive())
end)

-- Happy path ---------------------------------------------------------------

T.case("interrupt speaks with interrupt=true", function()
    setup()
    SpeechPipeline.speakInterrupt("hello")
    T.eq(#spoken, 1)
    T.eq(spoken[1].text, "hello")
    T.eq(spoken[1].interrupt, true)
end)

T.case("queued speaks with interrupt=false", function()
    setup()
    SpeechPipeline.speakQueued("hello")
    T.eq(#spoken, 1)
    T.eq(spoken[1].interrupt, false)
end)

-- Filtering is applied before speaking -------------------------------------

T.case("interrupt filters markup before speaking", function()
    setup()
    SpeechPipeline.speakInterrupt("[COLOR_X]hi[ENDCOLOR]")
    T.eq(spoken[1].text, "hi")
end)

T.case("queued filters markup before speaking", function()
    setup()
    SpeechPipeline.speakQueued("  hi\tthere  ")
    T.eq(spoken[1].text, "hi there")
end)

-- Empty / nil after filter -------------------------------------------------

T.case("nil input does not speak", function()
    setup()
    SpeechPipeline.speakInterrupt(nil)
    SpeechPipeline.speakQueued(nil)
    T.eq(#spoken, 0)
end)

T.case("empty string does not speak", function()
    setup()
    SpeechPipeline.speakInterrupt("")
    SpeechPipeline.speakQueued("")
    T.eq(#spoken, 0)
end)

T.case("markup that filters to empty does not speak", function()
    setup()
    SpeechPipeline.speakInterrupt("[COLOR_X][ENDCOLOR]")
    T.eq(#spoken, 0)
end)

-- Interrupt dedup window ---------------------------------------------------

T.case("same interrupt text within window is suppressed", function()
    setup()
    SpeechPipeline.speakInterrupt("hi")
    now = 0.04
    SpeechPipeline.speakInterrupt("hi")
    T.eq(#spoken, 1)
end)

T.case("same interrupt text after window speaks again", function()
    setup()
    SpeechPipeline.speakInterrupt("hi")
    now = 0.06
    SpeechPipeline.speakInterrupt("hi")
    T.eq(#spoken, 2)
end)

T.case("different interrupt text within window speaks", function()
    setup()
    SpeechPipeline.speakInterrupt("hi")
    SpeechPipeline.speakInterrupt("bye")
    T.eq(#spoken, 2)
end)

T.case("dedup compares the filtered form, not the raw input", function()
    -- Both raw strings filter to "hi"; second must be suppressed.
    setup()
    SpeechPipeline.speakInterrupt("  hi  ")
    SpeechPipeline.speakInterrupt("[COLOR_X]hi[ENDCOLOR]")
    T.eq(#spoken, 1)
end)

T.case("dedup window exactly at boundary suppresses", function()
    -- Window is "< 0.05", so now=0.05 is outside (speaks).
    setup()
    SpeechPipeline.speakInterrupt("hi")
    now = 0.05
    SpeechPipeline.speakInterrupt("hi")
    T.eq(#spoken, 2)
end)

-- Queued does not dedup ----------------------------------------------------

T.case("queued duplicates are not suppressed", function()
    setup()
    SpeechPipeline.speakQueued("hi")
    SpeechPipeline.speakQueued("hi")
    T.eq(#spoken, 2)
end)

T.case("queued does not populate the interrupt dedup window", function()
    -- A queued speak of "hi" must not block a subsequent interrupt "hi".
    setup()
    SpeechPipeline.speakQueued("hi")
    SpeechPipeline.speakInterrupt("hi")
    T.eq(#spoken, 2)
    T.eq(spoken[2].interrupt, true)
end)

T.case("interrupt dedup state does not block queued speech", function()
    setup()
    SpeechPipeline.speakInterrupt("hi")
    SpeechPipeline.speakQueued("hi")
    T.eq(#spoken, 2)
    T.eq(spoken[2].interrupt, false)
end)

-- stop() delegates ---------------------------------------------------------

T.case("stop delegates to SpeechEngine.stop", function()
    setup()
    SpeechPipeline.stop()
    T.eq(engineStopCount, 1)
end)

-- _reset -------------------------------------------------------------------

T.case("_reset clears dedup state", function()
    setup()
    SpeechPipeline.speakInterrupt("hi")
    SpeechPipeline._reset()
    SpeechPipeline.speakInterrupt("hi")
    T.eq(#spoken, 2)
end)

T.case("_reset re-enables a disabled pipeline", function()
    setup()
    SpeechPipeline.setEnabled(false)
    SpeechPipeline._reset()
    T.truthy(SpeechPipeline.isActive())
end)

os.exit(T.run() and 0 or 1)
