# Autologon-TekBlok-v2.ps1
# v2 DEGISIKLIGI: GPO-event (8001) tetikleyicisi artik Register-ScheduledTask
# CAGRISININ ICINDE, ilk kurulumla birlikte veriliyor. Onceki versiyonda
# event trigger'i "Get-ScheduledTask -> .Triggers += -> Set-ScheduledTask"
# ile SONRADAN eklemeye calisiyorduk; bu yontem bazi Windows surumlerinde
# CIM nesnesi uzerinde kalici olarak kaydolmuyor (sessizce basarisiz oluyor),
# bu yuzden GPO-event tetikleyicisi hic calismamis olabilir.
#
# Ayrica kurulum sirasinda registry degeri HEMEN de uygulanir (ilk restart'i
# beklemeden), boylece "kurulumdan sonraki ilk restart" de garanti calisir.
#
# BASKA CIHAZLARDA DA KULLANILABILIR: Kullanici adi, domain ve sifre
# calisma sirasinda elle sorulur - dosya icinde duzenleme GEREKMEZ.

# --- 0) Yonetici kontrolu ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "HATA: Bu script Yonetici olarak calistirilmiyor. PowerShell'i 'Yonetici olarak calistir' ile acip tekrar deneyin." -ForegroundColor Red
    return
}

# --- 1) Reassert-Autologon.ps1'i diske yaz ---
$reassertScript = @'
param(
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$Domain = "."
)
$ErrorActionPreference = "Stop"
$logPath = "C:\ProgramData\Autologon-Reassert\reassert.log"
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$ts] $msg"
}
try {
    $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $current = (Get-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon
    if ($current -eq "1") { Write-Log "AutoAdminLogon zaten 1." } else { Write-Log "AutoAdminLogon '$current' idi, 1'e cekiliyor." }
    Set-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon" -Value "1" -Type String
    Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName" -Value $Username -Type String
    Set-ItemProperty -Path $winlogonPath -Name "DefaultDomainName" -Value $Domain -Type String
    Remove-ItemProperty -Path $winlogonPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class LsaSecretHelper {
        [DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);
        [DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaStorePrivateData(IntPtr PolicyHandle, ref LSA_UNICODE_STRING KeyName, ref LSA_UNICODE_STRING PrivateData);
        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr PolicyHandle);
        [DllImport("advapi32.dll")]
        private static extern uint LsaNtStatusToWinError(uint status);
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public int Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
        public static void SetSecret(string key, string value) {
            LSA_UNICODE_STRING system = new LSA_UNICODE_STRING();
            LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
            IntPtr policyHandle;
            uint status = LsaOpenPolicy(ref system, ref oa, 0x00000400 | 0x00000800, out policyHandle);
            if (status != 0) throw new Exception("LsaOpenPolicy failed: " + LsaNtStatusToWinError(status));
            LSA_UNICODE_STRING keyName = new LSA_UNICODE_STRING();
            keyName.Buffer = Marshal.StringToHGlobalUni(key);
            keyName.Length = (ushort)(key.Length * 2);
            keyName.MaximumLength = (ushort)((key.Length + 1) * 2);
            LSA_UNICODE_STRING secretData = new LSA_UNICODE_STRING();
            secretData.Buffer = Marshal.StringToHGlobalUni(value);
            secretData.Length = (ushort)(value.Length * 2);
            secretData.MaximumLength = (ushort)((value.Length + 1) * 2);
            status = LsaStorePrivateData(policyHandle, ref keyName, ref secretData);
            LsaClose(policyHandle);
            Marshal.FreeHGlobal(keyName.Buffer);
            Marshal.FreeHGlobal(secretData.Buffer);
            if (status != 0) throw new Exception("LsaStorePrivateData failed: " + LsaNtStatusToWinError(status));
        }
    }
"@
    [LsaSecretHelper]::SetSecret("DefaultPassword", $Password)

    # Legal Notice banner'ini temizle (T2_Computer GPO'su zorluyor - bu banner
    # "OK" tiklanmadan oturum acilmasina izin vermedigi icin autologon'u
    # bloke ediyordu).
    $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $policyPath -Name "LegalNoticeCaption" -Value "" -Type String -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $policyPath -Name "LegalNoticeText" -Value "" -Type String -ErrorAction SilentlyContinue

    Write-Log "Basarili: AutoAdminLogon=1, kullanici=$Username, domain=$Domain, LegalNotice temizlendi - yeniden uygulandi."
}
catch { Write-Log "HATA: $($_.Exception.Message)" }
'@

New-Item -ItemType Directory -Force -Path "C:\ProgramData\Autologon-Reassert" | Out-Null
Set-Content -Path "C:\ProgramData\Autologon-Reassert\Reassert-Autologon.ps1" -Value $reassertScript -Encoding UTF8
Write-Host "1) Reassert-Autologon.ps1 diske yazildi." -ForegroundColor Cyan

# --- 2) Kullanici bilgisi + sifre: HEPSI ELLE SORULUYOR ---
$defaultUser   = $env:USERNAME
$defaultDomain = $env:USERDOMAIN

$UsernameInput = Read-Host "Autologon kullanici adi (varsayilan: $defaultUser, Enter'a basarak kabul edebilirsiniz)"
if ([string]::IsNullOrWhiteSpace($UsernameInput)) { $Username = $defaultUser } else { $Username = $UsernameInput }

$DomainInput = Read-Host "Domain / NETBIOS adi (yerel hesap icin bos birakip Enter'a basin -> '.'; varsayilan: $defaultDomain)"
if ([string]::IsNullOrWhiteSpace($DomainInput)) { $Domain = $defaultDomain } else { $Domain = $DomainInput }

$SecurePassword = Read-Host -AsSecureString "Autologon icin sifreyi girin ($Username)"
$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
)

Write-Host "Kullanilacak bilgiler -> Kullanici: $Username | Domain: $Domain" -ForegroundColor Cyan

# --- 2b) Registry degerini HEMEN simdi de uygula (ilk restart'i beklemeden) ---
& "C:\ProgramData\Autologon-Reassert\Reassert-Autologon.ps1" -Username $Username -Password $Password -Domain $Domain
Write-Host "1b) Registry hemen uygulandi (ilk boot icin garanti)." -ForegroundColor Cyan

# --- 3) GPO-event (8001) tetikleyicisini ONCEDEN olustur ---
# ONEMLI: Bu tetikleyici artik Register-ScheduledTask CAGRISININ ICINDE
# veriliyor, sonradan .Triggers += ile EKLENMIYOR. Onceki yontem bazi
# surumlerde sessizce basarisiz oluyordu.
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

# --- 4) Scheduled Task'i TUM tetikleyicilerle TEK SEFERDE kur ---
$taskName = "Reassert-Autologon"
$scriptPath = "C:\ProgramData\Autologon-Reassert\Reassert-Autologon.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Username `"$Username`" -Password `"$Password`" -Domain `"$Domain`""

$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# UC tetikleyici de (boot + 15dk tekrar + GPO-event) AYNI ANDA, tek cagriyla kuruluyor
Register-ScheduledTask -TaskName $taskName `
    -Action $action `
    -Trigger @($bootTrigger, $repeatTrigger, $eventTrigger) `
    -Principal $principal `
    -Settings $settings `
    -Description "GPO AutoAdminLogon resetini duzeltir (v2 - event trigger kurulumda dahil)." `
    -Force

Write-Host "2) Scheduled Task, 3 tetikleyiciyle (boot/15dk/GPO-event) kuruldu." -ForegroundColor Green

# --- 5) Dogrulama: tetikleyicilerin gercekten kayitli olup olmadigini goster ---
Write-Host "`n--- Kurulan Tetikleyiciler ---" -ForegroundColor Yellow
(Get-ScheduledTask -TaskName $taskName).Triggers | ForEach-Object {
    Write-Host ("  - " + $_.CimClass.CimClassName)
}

Write-Host "`nKURULUM TAMAMLANDI." -ForegroundColor Green
Write-Host "Loglar: C:\ProgramData\Autologon-Reassert\reassert.log" -ForegroundColor Yellow
Write-Host "Test icin: Get-ScheduledTask -TaskName '$taskName' | Start-ScheduledTask" -ForegroundColor Yellow
