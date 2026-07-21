$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = (Select-String -Path "$scriptDir\pubspec.yaml" -Pattern "^version:").Line.Split(":")[1].Trim()
cd $scriptDir
# Better Loop F1: gate the release build on the pre-release checks (tests +
# version consistency + encoding). No APK is produced if any check fails.
& "$scriptDir\prerelease_check.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Pre-release checks failed - aborting build, no APK produced."
    exit 1
}
flutter build apk --release 2>&1 | Select-Object -Last 20
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    $destPath = "d:\MyProjects\stock\stock-v$version.apk"
    Copy-Item $apkPath $destPath -Force
    $size = (Get-Item $destPath).Length / 1MB
    Write-Host "APK built: stock-v$version.apk ($([math]::Round($size, 1)) MB)"
} else {
    Write-Host "Build failed - APK not found"
}
