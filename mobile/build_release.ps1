$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = (Select-String -Path "$scriptDir\pubspec.yaml" -Pattern "^version:").Line.Split(":")[1].Trim()
cd $scriptDir
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
