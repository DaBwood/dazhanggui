# 从雷电模拟器拉取《叫我大掌柜》的热更 / 远程资源
# 用法（先启动雷电和游戏，进一次门客/挚友/皮肤页面）：
#   powershell -ExecutionPolicy Bypass -File tools\pull_ldplayer.ps1
#
# 输出到 C:\Users\林\Documents\大掌柜_assets\hotupdate\
# 不会写进 Godot 工程目录。

param(
    [string]$Adb = 'D:\leidian\LDPlayer9\adb.exe',
    [string]$Package = 'com.sqw.jwdzg.jwdzg_pz',
    [string]$Serial = 'emulator-5554',
    [string]$Out = 'C:\Users\林\Documents\大掌柜_assets\hotupdate'
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Adb)) {
    Write-Host "找不到 adb：$Adb" -ForegroundColor Red
    Write-Host "请确认雷电装在 D:\leidian\LDPlayer9，或改 -Adb 参数。"
    exit 1
}

Write-Host "== 连接雷电 ==" -ForegroundColor Cyan
& $Adb connect 127.0.0.1:5555 | Out-Host
& $Adb devices | Out-Host

$pkgs = & $Adb -s $Serial shell pm list packages $Package 2>&1
if (($pkgs -join "`n") -notmatch [regex]::Escape($Package)) {
    Write-Host "没找到包 $Package。" -ForegroundColor Yellow
    Write-Host "先启动雷电和游戏；如果装了多个模拟器，试 -Adb 指向对应目录。"
    exit 2
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$dataDir = Join-Path $Out 'data'
$sdDir = Join-Path $Out 'sdcard'
New-Item -ItemType Directory -Force -Path $dataDir, $sdDir | Out-Null

Write-Host "== 检查 root ==" -ForegroundColor Cyan
$id = (& $Adb -s $Serial shell su -c id 2>&1) -join "`n"
$hasRoot = $id -match 'uid=0'

if ($hasRoot) {
    Write-Host "root 可用，拉 /data/data/$Package" -ForegroundColor Green
    & $Adb -s $Serial shell "su -c 'tar -czf /sdcard/dzg_data.tar.gz /data/data/$Package'" | Out-Host
    & $Adb -s $Serial pull /sdcard/dzg_data.tar.gz (Join-Path $Out 'dzg_data.tar.gz') | Out-Host
    $tar = Join-Path $Out 'dzg_data.tar.gz'
    if (Test-Path $tar) {
        tar -xzf $tar -C $dataDir
        Write-Host "已解压到 $dataDir"
    }
} else {
    Write-Host "root 没开：雷电设置 -> 其他设置 -> ROOT 权限 -> 开启，重启模拟器再来。" -ForegroundColor Yellow
}

Write-Host "== 拉 /sdcard/Android/data/$Package ==" -ForegroundColor Cyan
& $Adb -s $Serial shell "tar -czf /sdcard/dzg_android.tar.gz /sdcard/Android/data/$Package" | Out-Host
& $Adb -s $Serial pull /sdcard/dzg_android.tar.gz (Join-Path $Out 'dzg_android.tar.gz') | Out-Host
$tar2 = Join-Path $Out 'dzg_android.tar.gz'
if (Test-Path $tar2) {
    tar -xzf $tar2 -C $sdDir
    Write-Host "已解压到 $sdDir"
}

Write-Host "== 结果 ==" -ForegroundColor Cyan
Get-ChildItem $Out -Recurse -File -ErrorAction SilentlyContinue |
    Group-Object Extension |
    Sort-Object Count -Descending |
    Select-Object Name, Count |
    Format-Table -AutoSize

Write-Host "下一步：把 $Out 里的 .bin / .pkm / .json 清单发我，或直接让我扫。"
