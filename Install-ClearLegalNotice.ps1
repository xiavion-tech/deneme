# Install-ClearLegalNotice.ps1
# Clear-LegalNotice.ps1'i SYSTEM baglaminda, GPO-event (8001) + boot + 1 dk
# tekrar tetikleyicileriyle calisacak sekilde AYRI bir Scheduled Task olarak
# kurar. AutoAdminLogon (Reassert-Autologon) task'indan BAGIMSIZDIR.
#
# Yonetici olarak calistirin.

$ErrorActionPreference = "Stop"

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "HATA: Bu script Yonetici olarak calistirilmiyor." -ForegroundColor Red
    return
}

# --- 1) Clear-LegalNotice.ps1'i diske yaz ---
$clearScript = @'
param(
    [Parameter(Mandatory = $true)][string]$Username,
    [string]$Domain = "."
)
$ErrorActionPreference = "Stop"
$logPath = "C:\ProgramData\Autologon-Reassert\legalnotice.log"
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$ts] $msg"
}
try {
    $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $currentCaption = (Get-ItemProperty -Path $policyPath -Name "LegalNoticeCaption" -ErrorAction SilentlyContinue).LegalNoticeCaption
    $currentText    = (Get-ItemProperty -Path $policyPath -Name "LegalNoticeText" -ErrorAction SilentlyContinue).LegalNoticeText
    if ([string]::IsNullOrEmpty($currentCaption) -and [string]::IsNullOrEmpty($currentText)) {
        Write-Log "LegalNotice zaten bos."
    } else {
        Write-Log "LegalNotice dolu bulundu (GPO tarafindan resetlenmis), temizleniyor."
        Set-ItemProperty -Path $policyPath -Name "LegalNoticeCaption" -Value "" -Type String
        Set-ItemProperty -Path $policyPath -Name "LegalNoticeText" -Value "" -Type String
        Write-Log "Basarili: LegalNoticeCaption ve LegalNoticeText temizlendi."
    }
}
catch { Write-Log "HATA: $($_.Exception.Message)" }
'@

New-Item -ItemType Directory -Force -Path "C:\ProgramData\Autologon-Reassert" | Out-Null
Set-Content -Path "C:\ProgramData\Autologon-Reassert\Clear-LegalNotice.ps1" -Value $clearScript -Encoding UTF8
Write-Host "1) Clear-LegalNotice.ps1 diske yazildi." -ForegroundColor Cyan

# --- 2) Kullanici bilgisi (sadece log/dogrulama icin, SYSTEM yetkisiyle calisir) ---
$defaultUser = $env:USERNAME
$UsernameInput = Read-Host "Kullanici adi (log icin, varsayilan: $defaultUser)"
if ([string]::IsNullOrWhiteSpace($UsernameInput)) { $Username = $defaultUser } else { $Username = $UsernameInput }

# --- 2b) Hemen simdi de uygula ---
& "C:\ProgramData\Autologon-Reassert\Clear-LegalNotice.ps1" -Username $Username
Write-Host "1b) LegalNotice hemen temizlendi." -ForegroundColor Cyan

# --- 3) GPO-event (8001) tetikleyicisi ---
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

# --- 4) Boot + 1 dk tekrar tetikleyicileri ---
$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# --- 5) Task'i SYSTEM baglaminda, AutoAdminLogon task'indan AYRI isimle kur ---
$taskName = "Clear-LegalNotice"
$scriptPath = "C:\ProgramData\Autologon-Reassert\Clear-LegalNotice.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Username `"$Username`""

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger @($bootTrigger, $repeatTrigger, $eventTrigger) `
    -Principal $principal `
    -Settings $settings `
    -Description "GPO (T2_Computer) Legal Notice banner'ini temizler - AutoAdminLogon task'indan bagimsiz." `
    -Force

Write-Host "2) Scheduled Task 'Clear-LegalNotice' (boot/1dk/GPO-event) kuruldu." -ForegroundColor Green

Write-Host "`n--- Kurulan Tetikleyiciler ---" -ForegroundColor Yellow
(Get-ScheduledTask -TaskName $taskName).Triggers | ForEach-Object {
    Write-Host ("  - " + $_.CimClass.CimClassName)
}

Write-Host "`nKURULUM TAMAMLANDI." -ForegroundColor Green
Write-Host "Loglar: C:\ProgramData\Autologon-Reassert\legalnotice.log" -ForegroundColor Yellow
Write-Host "Test icin: Get-ScheduledTask -TaskName '$taskName' | Start-ScheduledTask" -ForegroundColor Yellow
