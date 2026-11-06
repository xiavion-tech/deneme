# Clear-LegalNotice.ps1
# GPO (T2_Computer) tarafindan zorlanan "Interactive logon: Message title/text
# for users attempting to log on" (Legal Notice banner) degerlerini temizler.
# Bu banner, OK'a tiklanmadan oturum acilmasina izin vermedigi icin autologon'u
# bloke ediyordu.
#
# AutoAdminLogon mekanizmasindan TAMAMEN BAGIMSIZDIR - ayri bir Scheduled
# Task olarak calisir, ayri bir log tutar.
#
# Yonetici (SYSTEM) baglaminda calismalidir - Task Scheduler ile kurulacak.

param(
    [Parameter(Mandatory = $true)][string]$Username,  # dogrulama/log amacli, SYSTEM baglaminda calisir
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
catch {
    Write-Log "HATA: $($_.Exception.Message)"
}
