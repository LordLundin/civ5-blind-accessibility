# Runs the offline Lua test suite using the bundled 5.1.5 interpreter.
# Must be invoked from the repo root.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $root

$lua = Join-Path $root "third_party\lua51\lua5.1.exe"
if (-not (Test-Path $lua)) {
    Write-Error "Missing interpreter: $lua"
    exit 2
}

$suites = @(
    "tests/text_filter_test.lua",
    "tests/speech_pipeline_test.lua"
)

$failed = 0
foreach ($suite in $suites) {
    Write-Host "=== $suite ==="
    & $lua "-e" "package.path='tests/?.lua;'..package.path" $suite
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

if ($failed -gt 0) {
    Write-Host "$failed suite(s) failed."
    exit 1
}
Write-Host "All suites passed."
