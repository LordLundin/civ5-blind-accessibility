-- Entry point. Aggregates all suites into a single runner and exit code.
-- Invoked by test.ps1 with the repo root as CWD.

local T = require("support")

-- Shared global stubs suites depend on. Individual suites may mutate Log
-- (e.g. TextFilter's warn-capture tests) and SpeechEngine.stop (pipeline
-- tests) in their own setup() — that's the seam.
Log = {
    debug = function() end, info = function() end,
    warn  = function() end, error = function() end,
}
SpeechEngine = {
    say  = function() end,
    stop = function() end,
}

T.register("text_filter", require("text_filter_test"))
T.register("speech_pipeline", require("speech_pipeline_test"))

os.exit(T.run() and 0 or 1)
