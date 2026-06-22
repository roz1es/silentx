param(
  [string]$ApiUrl = "https://silentx.ru",
  [string]$UpdateUrl = "https://silentx.ru/desktop/windows/latest.json",
  [string]$DownloadBaseUrl = "https://silentx.ru/desktop/windows",
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$DesktopRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RepoRoot = Resolve-Path (Join-Path $DesktopRoot "..")
$PubspecPath = Join-Path $DesktopRoot "pubspec.yaml"
$IssPath = Join-Path $PSScriptRoot "brenkschat.iss"
$SourceDir = Join-Path $DesktopRoot "build\windows\x64\runner\$Configuration"
$ReleaseDir = Join-Path $DesktopRoot "release\windows"

function Find-Iscc {
  $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  throw "Не найден Inno Setup 6. Установите его: https://jrsoftware.org/isdl.php"
}

function Read-AppVersion {
  $pubspec = Get-Content $PubspecPath -Raw
  if ($pubspec -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
    return $Matches[1]
  }
  return "0.1.0"
}

Write-Host "==> BrenksChat Windows installer" -ForegroundColor Cyan
Write-Host "Desktop: $DesktopRoot"
Write-Host "API URL: $ApiUrl"
$AppVersion = Read-AppVersion
Write-Host "Version: $AppVersion"
Write-Host "Update manifest: $UpdateUrl"

Push-Location $DesktopRoot
try {
  flutter pub get
  flutter build windows --release `
    --dart-define=BRENKS_API_URL=$ApiUrl `
    --dart-define=BRENKS_APP_VERSION=$AppVersion `
    --dart-define=BRENKS_UPDATE_URL=$UpdateUrl
}
finally {
  Pop-Location
}

if (!(Test-Path (Join-Path $SourceDir "BrenksChat.exe"))) {
  throw "Не найден BrenksChat.exe в $SourceDir"
}

New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null

$Iscc = Find-Iscc

Write-Host "==> Inno Setup: $Iscc" -ForegroundColor Cyan
& $Iscc `
  "/DAppVersion=$AppVersion" `
  "/DSourceDir=$SourceDir" `
  $IssPath

$InstallerPath = Join-Path $ReleaseDir "BrenksChatSetup-$AppVersion.exe"
$ManifestPath = Join-Path $ReleaseDir "latest.json"
$InstallerFileName = Split-Path $InstallerPath -Leaf
$Manifest = [ordered]@{
  version = $AppVersion
  url = "$DownloadBaseUrl/$InstallerFileName"
  notes = "Обновление БренксЧат $AppVersion."
  publishedAt = (Get-Date).ToUniversalTime().ToString("o")
}
$Manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestPath -Encoding UTF8

Write-Host "==> Готово: $InstallerPath" -ForegroundColor Green
Write-Host "==> Manifest: $ManifestPath" -ForegroundColor Green
