# Care — Reproducible Android ARM64 APK Build Script (Windows)
param(
  [ValidateSet("debug", "release")]
  [string]$Mode = "debug"
)

$ErrorActionPreference = "Stop"

$env:JAVA_HOME = "C:\src\jdk-17"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PATH = "C:\src\flutter\bin;C:\src\jdk-17\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $root "app"

if (-not (Test-Path (Join-Path $root "runtime\out\arm64-v8a\assets\runtime\manifest.json"))) {
  Write-Warning "runtime/out/arm64-v8a not found. Building Care APK shell (Direct BYOK works immediately; run runtime/build-runtime.sh arm64-v8a on Linux/WSL to bundle the full offline PRoot rootfs)."
}

Push-Location $appDir
try {
  flutter pub get
  flutter analyze
  flutter test
  flutter build apk --flavor arm64 "--$Mode"
} finally {
  Pop-Location
}
