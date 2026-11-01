# Pull LDPlayer game data (hot-update/skin cache, APK, OBB) for costume extraction.
#
# All-ASCII on purpose: Windows PowerShell 5.1 reads UTF-8-without-BOM as ANSI,
# so Chinese paths/prompts in the script get mangled.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\pull_ldplayer_assets.ps1
#   powershell -ExecutionPolicy Bypass -File tools\pull_ldplayer_assets.ps1 -Adb "D:\leidian\LDPlayer9\adb.exe"
#
# Before running: enable ROOT in LDPlayer
#   LDPlayer menu -> Settings -> Other settings -> ROOT permission -> enable -> save -> restart.

param(
    [string]$Adb = "",
    [string]$Serial = "",
    [string]$Out = "D:\dzg_pull",
    [switch]$CacheOnly
)

$ErrorActionPreference = "Continue"

if (-not $Adb) {
    $candidates = @(
        "D:\leidian\LDPlayer9\adb.exe",
        "C:\LDPlayer\LDPlayer9\adb.exe",
        "C:\LDPlayer\LDPlayer64\adb.exe",
        "C:\LDPlayer\LDPlayer\adb.exe",
        "C:\ChangZhi\LDPlayer\adb.exe",
        "D:\LDPlayer\LDPlayer9\adb.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $Adb = $c; break }
    }
}
if (-not $Adb -or -not (Test-Path $Adb)) {
    Write-Host "adb.exe not found. Pass it explicitly with -Adb." -ForegroundColor Yellow
    exit 1
}
Write-Host "adb: $Adb"

function Get-DeviceSerials {
    $lines = @(& $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice$" })
    $serials = @()
    foreach ($line in $lines) { $serials += ($line -split "\s+")[0] }
    return $serials
}

$serials = @(Get-DeviceSerials)
if (-not $Serial) {
    if ($serials.Count -eq 0) {
        Write-Host "No device, trying adb connect 127.0.0.1:5555 ..." -ForegroundColor Yellow
        & $Adb connect 127.0.0.1:5555 | Out-Null
        Start-Sleep -Seconds 1
        $serials = @(Get-DeviceSerials)
    }
    if ($serials.Count -eq 0) {
        Write-Host "No device. Start LDPlayer first, then rerun." -ForegroundColor Yellow
        & $Adb devices
        exit 1
    }
    $emulator = $serials | Where-Object { $_ -match "^emulator-" } | Select-Object -First 1
    if ($emulator) { $Serial = $emulator } else { $Serial = $serials[0] }
}

Write-Host "Using serial: $Serial" -ForegroundColor Green
$serials | ForEach-Object { Write-Host "  available: $_" }

# If both transports exist, drop the TCP one so adb does not warn about duplicates.
if (($serials -contains "127.0.0.1:5555") -and ($Serial -ne "127.0.0.1:5555")) {
    & $Adb disconnect 127.0.0.1:5555 | Out-Null
    Write-Host "Disconnected duplicate 127.0.0.1:5555" -ForegroundColor Yellow
}

Write-Host "`nPackages matching dzg / ngty / guizhang / tmgp:" -ForegroundColor Cyan
$pkgs = @(& $Adb -s $Serial shell pm list packages |
    Select-String -Pattern "dzg|ngty|guizhang|tmgp" |
    ForEach-Object { $_.Line -replace "^package:", "" })
if ($pkgs.Count -eq 0) {
    Write-Host "No matching package; first 40 packages:" -ForegroundColor Yellow
    & $Adb -s $Serial shell pm list packages | Select-Object -First 40
    exit 1
}
$pkgs | ForEach-Object { Write-Host "  $_" }
$pkg = $pkgs[0]
Write-Host "Using package: $pkg" -ForegroundColor Green

# Root check
$id = & $Adb -s $Serial shell id
Write-Host "shell id: $id"
if ($id -notmatch "uid=0") {
    Write-Host "Trying adb root..." -ForegroundColor Yellow
    & $Adb -s $Serial root | Out-Null
    Start-Sleep -Seconds 2
    & $Adb -s $Serial wait-for-device | Out-Null
    $id = & $Adb -s $Serial shell id
    Write-Host "shell id after root: $id"
}
if ($id -notmatch "uid=0") {
    Write-Host "Not root. Enable ROOT in LDPlayer settings, restart, then rerun." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

if ($CacheOnly) {
    Write-Host "`nPulling cache only ..." -ForegroundColor Cyan
    & $Adb -s $Serial shell "tar czf /sdcard/dzg_cache.tar.gz /data/data/$pkg/cache 2>/dev/null || tar czf /sdcard/dzg_cache.tar.gz /sdcard/Android/data/$pkg/cache"
    & $Adb -s $Serial pull /sdcard/dzg_cache.tar.gz "$Out\dzg_cache.tar.gz"
    Write-Host "Done. Output: $Out\dzg_cache.tar.gz" -ForegroundColor Green
    exit 0
}

Write-Host "`nPulling /data/data/$pkg/files ..." -ForegroundColor Cyan
& $Adb -s $Serial shell "tar czf /sdcard/dzg_files.tar.gz /data/data/$pkg/files 2>/dev/null || tar czf /sdcard/dzg_files.tar.gz /sdcard/Android/data/$pkg/files"
& $Adb -s $Serial pull /sdcard/dzg_files.tar.gz "$Out\dzg_files.tar.gz"

Write-Host "`nPulling APK ..." -ForegroundColor Cyan
$apkPaths = @(& $Adb -s $Serial shell pm path $pkg | ForEach-Object { $_ -replace "^package:", "" })
$i = 0
foreach ($p in $apkPaths) {
    & $Adb -s $Serial pull $p "$Out\apk_$i.apk"
    $i++
}

Write-Host "`nPulling OBB (if any) ..." -ForegroundColor Cyan
& $Adb -s $Serial pull "/sdcard/Android/obb/$pkg" "$Out\obb"

Write-Host "`nDone. Output: $Out" -ForegroundColor Green
Write-Host "Zip that folder (or just dzg_files.tar.gz) and tell me the path."
