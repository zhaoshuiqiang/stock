# Better Loop F5: single durable pre-release validation owner.
#
# Replaces the scattered one-off fix_*/patch_* rituals with one script that must
# pass before an APK is produced. It runs:
#   1. flutter analyze   (informational; does not block)
#   2. flutter test      (HARD gate) - the suite already contains the
#      version-consistency guard (version_consistency_test.dart) and the source
#      encoding guard (source_encoding_guard_test.dart), so a single `flutter
#      test` pass covers tests + version sync + encoding in one step.
#
# Exit code 0 = all gates green (safe to build); non-zero = do NOT build.
# Usage: powershell -File mobile/prerelease_check.ps1 [-SkipAnalyze]
param(
    [switch]$SkipAnalyze
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

if (-not $SkipAnalyze) {
    Write-Host "[prerelease] flutter analyze (informational)..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[prerelease] WARNING: flutter analyze reported issues (not blocking)."
    }
}

Write-Host "[prerelease] flutter test (hard gate: all suites + version + encoding)..."
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "[prerelease] FAIL: tests failed (exit $LASTEXITCODE). No APK should be built."
    exit 1
}

Write-Host "[prerelease] PASS: all pre-release checks are green."
exit 0
