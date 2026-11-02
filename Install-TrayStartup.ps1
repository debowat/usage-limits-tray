# Adds Tray-Limits.ps1 to the Windows Startup folder (remove: delete 'Usage limits tray.lnk' in shell:startup).
$f = Join-Path $PSScriptRoot 'Tray-Limits.ps1'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Usage limits tray.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments = "-STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$f`""
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle = 7
$s.Save()
"Aangemaakt: $lnk"
