param(
  [string]$Version = "",
  [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $Version) {
  $line = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
  if (-not $line) { throw "Cannot read version from pubspec.yaml" }
  $Version = $line.Matches[0].Groups[1].Value
}
Write-Host "Version: $Version"

if (-not $NoBuild) {
  Write-Host "Building Windows release..."
  & (Join-Path $root "tools\flutter.cmd") build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
}

$release = Join-Path $root "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $release "NEUBetterPro.exe"))) {
  throw "Build output not found: $release\NEUBetterPro.exe"
}

$isccCandidates = @(
  (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
  (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
  "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $isccCandidates) {
  throw "ISCC.exe not found. Install Inno Setup 6 (winget install JRSoftware.InnoSetup)."
}
$iscc = @($isccCandidates) | Select-Object -First 1
Write-Host "Using ISCC: $iscc"

$iss = Join-Path $root "installer\windows\NEUBetterPro.iss"
& $iscc "/DMyAppVersion=$Version" "/Qp" $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed (exit $LASTEXITCODE)" }

$out = Join-Path $root "dist\NEU-Better-$Version-windows-x64-setup.exe"
if (-not (Test-Path $out)) { throw "Installer output not found: $out" }
$item = Get-Item $out
Write-Host ("Installer: {0} ({1:N0} bytes)" -f $item.FullName, $item.Length)
