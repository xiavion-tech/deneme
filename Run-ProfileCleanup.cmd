@echo off
REM Bu dosyayi yonetici (Administrator) olarak calistirin.
REM Execution Policy kisitlamasini bu oturuma ozel bypass eder, sistem ayarini degistirmez.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-StaleProfiles.ps1"

echo.
echo Islem tamamlandi. Devam etmek icin bir tusa basin...
pause >nul
