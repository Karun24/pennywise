# PennyWise one-time setup for Windows.
# Run from this folder:   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# What it does:
#   1. Checks Flutter is installed.
#   2. Generates the Android/iOS platform folders (keeps every existing file).
#   3. Sets the app name to "PennyWise" on Android and iOS.
#   4. Runs: flutter pub get, dart format, flutter analyze, flutter test.

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Magenta }

Step 'Checking Flutter'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Flutter was not found on PATH. Install it from https://docs.flutter.dev/get-started/install/windows/mobile and re-open PowerShell.' -ForegroundColor Red
    exit 1
}
flutter --version

Step 'Generating platform folders (existing files are NOT overwritten)'
flutter create --org com.pennywise --project-name pennywise --platforms android,ios .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Step 'Setting the display name to PennyWise'
$manifest = 'android/app/src/main/AndroidManifest.xml'
if (Test-Path $manifest) {
    $text = (Get-Content $manifest -Raw) -replace 'android:label="[^"]*"', 'android:label="PennyWise"'
    [System.IO.File]::WriteAllText((Resolve-Path $manifest), $text)
}
$plist = 'ios/Runner/Info.plist'
if (Test-Path $plist) {
    $text = Get-Content $plist -Raw
    $text = $text -replace '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', '${1}PennyWise${2}'
    $text = $text -replace '(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)', '${1}PennyWise${2}'
    [System.IO.File]::WriteAllText((Resolve-Path $plist), $text)
}

Step 'flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host 'pub get failed. If a package version is too old for your Flutter SDK, run:  flutter pub upgrade --major-versions' -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Step 'dart format'
dart format lib test

Step 'flutter analyze'
flutter analyze
$analyze = $LASTEXITCODE

Step 'flutter test'
flutter test
$tests = $LASTEXITCODE

Write-Host ''
if ($analyze -eq 0 -and $tests -eq 0) {
    Write-Host 'All checks passed. Connect your phone (USB debugging on) and run:  flutter run' -ForegroundColor Green
} else {
    Write-Host "Analyze exit code: $analyze, test exit code: $tests. Copy the output above back to Claude to fix." -ForegroundColor Yellow
}
