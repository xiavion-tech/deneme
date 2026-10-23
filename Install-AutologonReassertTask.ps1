# Install-AutologonReassertTask.ps1
# Reassert-Autologon.ps1'i SYSTEM baglaminda, asagidaki tetikleyicilerle
# calisacak sekilde Scheduled Task olarak kurar:
#
#   1) Group Policy "basariyla islendi" event'i (Event ID 8001,
#      log: Microsoft-Windows-GroupPolicy/Operational) - GPO her
#      AutoAdminLogon'u resetledikten saniyeler sonra bizim script
#      tekrar 1'e cekiyor.
#   2) Her sistem acilisinda (yedek/garanti).
#   3) Her 30 dakikada bir tekrar (GPO'nun arka plan refresh periyoduna
#      karsi ek guvence).
#
# Yonetici olarak calistirin.

param(
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $false)][SecureString]$SecurePassword,
    [string]$Domain = ".",
    [string]$ScriptDestination = "C:\ProgramData\Autologon-Reassert\Reassert-Autologon.ps1"
)

$ErrorActionPreference = "Stop"

# Sifre parametre olarak verilmediyse, ekranda gozukmeyecek sekilde sorulur
# (PowerShell komut gecmisinde duz metin olarak kalmaz).
if (-not $SecurePassword) {
    $SecurePassword = Read-Host -AsSecureString "Autologon icin sifreyi girin ($Username)"
}
$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
)

# 1) Scripti kalici bir konuma kopyala
New-Item -ItemType Directory -Force -Path (Split-Path $ScriptDestination) | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot "Reassert-Autologon.ps1") -Destination $ScriptDestination -Force

$taskName = "Reassert-Autologon"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDestination`" -Username `"$Username`" -Password `"$Password`" -Domain `"$Domain`""

# --- Tetikleyici 1: Group Policy basari event'i (8001) ---
# Task Scheduler GUI'den tetiklenemeyen "custom event" tetikleyicisini
# CIM/Register-ScheduledTask ile XML CIM tetikleyici olarak ekliyoruz.
$eventTriggerXml = @'
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-GroupPolicy/Operational">
    <Select Path="Microsoft-Windows-GroupPolicy/Operational">*[System[(EventID=8001)]]</Select>
  </Query>
</QueryList>
'@

$CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$eventTrigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
$eventTrigger.Subscription = $eventTriggerXml
$eventTrigger.Enabled = $true

# --- Tetikleyici 2: Sistem acilisi ---
$bootTrigger = New-ScheduledTaskTrigger -AtStartup

# --- Tetikleyici 3: Her 30 dakikada bir, surekli ---
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger @($bootTrigger, $repeatTrigger) `
    -Principal $principal `
    -Settings $settings `
    -Description "GPO (T2_Computer) AutoAdminLogon'u resetledikten sonra otomatik olarak yeniden uygular." `
    -Force

# Event tetikleyiciyi ayrica CIM uzerinden ekliyoruz (Register-ScheduledTask
# bazi PowerShell surumlerinde ozel event trigger'i dogrudan kabul etmiyor)
$task = Get-ScheduledTask -TaskName $taskName
$task.Triggers += $eventTrigger
Set-ScheduledTask -InputObject $task | Out-Null

Write-Host "Scheduled Task '$taskName' kuruldu." -ForegroundColor Green
Write-Host "Loglar: C:\ProgramData\Autologon-Reassert\reassert.log" -ForegroundColor Yellow
Write-Host "Test icin: Get-ScheduledTask -TaskName '$taskName' | Start-ScheduledTask" -ForegroundColor Yellow
