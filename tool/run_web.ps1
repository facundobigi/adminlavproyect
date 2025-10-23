param(
  [switch]$Clean,
  [switch]$Release,
  [ValidateSet('chrome','edge')]
  [string]$Device = 'chrome',
  [string]$Hostname = '127.0.0.1',
  [int]$Port = 51700,
  [int]$DdsPort = 51701,
  [switch]$DisableExtensions = $true,
  [switch]$FreshProfile = $true
)

$ErrorActionPreference = 'Stop'

# Move to project root (../ from this script directory)
$projRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $projRoot

Write-Host "Project root:" (Get-Location)

if ($Clean) {
  Write-Host "Cleaning project (flutter clean + removing .dart_tool/build)..." -ForegroundColor Yellow
  flutter clean | Out-Host
  foreach ($p in @('.dart_tool','build')) {
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host "Fetching packages..." -ForegroundColor Yellow
flutter pub get | Out-Host

$argsList = @('run','-d', $Device)
if ($Release) { $argsList += '--release' }

# Stable web flags
$argsList += @(
  "--web-hostname=$Hostname",
  "--web-port=$Port",
  "--dds-port=$DdsPort"
)

if ($DisableExtensions) {
  $argsList += @('--web-browser-flag','--disable-extensions')
}
if ($FreshProfile) {
  $profileDir = Join-Path $env:TEMP 'flutter_web_profile'
  $argsList += @('--web-browser-flag',"--user-data-dir=$profileDir")
}

Write-Host "Launching: flutter $($argsList -join ' ')" -ForegroundColor Green
flutter @argsList

