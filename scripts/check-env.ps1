# Care — Local Windows Dev Environment Verification Script
$ErrorActionPreference = "Continue"

Write-Host "=== Care Full-Stack Toolchain Check ===" -ForegroundColor Cyan

$checks = @(
  @{ Name = "Node.js (24.x)"; Cmd = "node"; Args = @("-v") },
  @{ Name = "npm"; Cmd = "npm"; Args = @("-v") },
  @{ Name = "Git"; Cmd = "git"; Args = @("--version") },
  @{ Name = "JDK 17 (C:\src\jdk-17)"; Path = "C:\src\jdk-17\bin\java.exe"; Args = @("-version") },
  @{ Name = "Flutter SDK (C:\src\flutter)"; Path = "C:\src\flutter\bin\flutter.bat"; Args = @("--version") },
  @{ Name = "Android CLI"; Path = "$env:USERPROFILE\AppData\AndroidCLI\android.exe"; Args = @("--version") },
  @{ Name = "ADB (platform-tools)"; Path = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"; Args = @("version") }
)

foreach ($c in $checks) {
  $exe = if ($c.Path) { if (Test-Path $c.Path) { $c.Path } else { $null } } else { (Get-Command $c.Cmd -ErrorAction SilentlyContinue).Source }
  if ($exe) {
    $out = (& $exe @($c.Args) 2>&1 | Select-Object -First 2) -join " | "
    Write-Host "[OK]   $($c.Name): $out" -ForegroundColor Green
  } else {
    Write-Host "[MISS] $($c.Name)" -ForegroundColor Yellow
  }
}

Write-Host "`n=== Upstream Snapshots ===" -ForegroundColor Cyan
foreach ($u in @("upstream/DS-Bot/ds-bot/package.json", "upstream/dsh-Go/app/pubspec.yaml")) {
  if (Test-Path $u) { Write-Host "[OK]   $u" -ForegroundColor Green }
  else { Write-Host "[MISS] $u" -ForegroundColor Yellow }
}
