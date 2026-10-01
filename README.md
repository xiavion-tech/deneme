# deneme
Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and -not $_.Loaded } | Remove-CimInstance -ErrorAction SilentlyContinue

Get-CimInstance Win32_UserProfile | Select LocalPath, Loaded, Special
