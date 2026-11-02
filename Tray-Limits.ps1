# Windows tray icons with the Claude and Codex account limits (5-hour window fills the logo).
# Start: powershell -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File Tray-Limits.ps1
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI.

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Win32 -Name Icons -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);'

# Every = poll every N minutes (the Claude usage endpoint answers 429 when polled every minute).
$providers = [ordered]@{
    claude = @{ Label = 'Claude'; Logo = 'claude.ico'; Every = 5 }
    codex  = @{ Label = 'Codex';  Logo = 'codex.ico';  Every = 1 }
}
foreach ($p in $providers.Values) {
    $p.Mask = (New-Object Drawing.Icon (Join-Path $PSScriptRoot "icons\$($p.Logo)"), 32, 32).ToBitmap()
    $p.State = $null
}

# Grey logo silhouette that fills up from the bottom with the 5-hour usage.
function New-LimitIcon($mask, $percent, $stale) {
    $grey = [Drawing.Color]::FromArgb(150, 150, 150)
    $fill = if ($null -eq $percent -or $stale) { $grey }
            elseif ($percent -ge 90) { [Drawing.Color]::FromArgb(232, 72, 61) }
            elseif ($percent -ge 70) { [Drawing.Color]::FromArgb(245, 166, 35) }
            else { [Drawing.Color]::FromArgb(76, 200, 110) }
    $level = if ($null -eq $percent) { 0 } else { [math]::Min($percent, 100) / 100 }
    $fillTop = $mask.Height - [math]::Round($mask.Height * $level)
    $bmp = New-Object Drawing.Bitmap $mask.Width, $mask.Height
    for ($y = 0; $y -lt $mask.Height; $y++) {
        $c = if ($y -ge $fillTop) { $fill } else { $grey }
        for ($x = 0; $x -lt $mask.Width; $x++) {
            $a = $mask.GetPixel($x, $y).A
            if ($a) { $bmp.SetPixel($x, $y, [Drawing.Color]::FromArgb($a, $c)) }
        }
    }
    $handle = $bmp.GetHicon(); $bmp.Dispose()
    [Drawing.Icon]::FromHandle($handle)
}

function Format-When($unix) {
    $at = [DateTimeOffset]::FromUnixTimeSeconds([long]$unix).LocalDateTime
    $today = (Get-Date).Date
    if ($at.Date -eq $today) { 'om ' + $at.ToString('HH:mm') }
    elseif ($at.Date -eq $today.AddDays(1)) { 'morgen ' + $at.ToString('HH:mm') }
    else { $at.ToString('ddd d/M HH:mm', [Globalization.CultureInfo]'nl-BE') }
}

function Format-Window($w, $name) {
    if (-not $w) { return $null }
    $when = if ($w.resetsAt) { Format-When $w.resetsAt } else { '?' }
    if ($w.usedPercent -ge 100) { return "${name}: OP - weer vrij $when" }
    "${name}: $([int]$w.usedPercent)% gebruikt (reset $when)"
}

# NotifyIcon.Text refuses more than 63 characters; the shell itself allows 127.
function Set-TrayText($icon, $text) {
    $flags = [Reflection.BindingFlags]'NonPublic, Instance'
    [Windows.Forms.NotifyIcon].GetField('text', $flags).SetValue($icon, $text.Substring(0, [math]::Min(127, $text.Length)))
    if ($icon.Visible) { [void][Windows.Forms.NotifyIcon].GetMethod('UpdateIcon', $flags).Invoke($icon, @($true)) }
}

# Use the py launcher when installed, otherwise python3 or python from PATH.
$Python = @('py', 'python3', 'python' | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue })[0]
$PyArgs = if ($Python -eq 'py') { @('-3') } else { @() }

# Returns the provider's windows, or $null when the read failed.
function Read-Limits($key) {
    $json = & $Python @PyArgs (Join-Path $PSScriptRoot 'limits.py') $key 2> $null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    try { $json | ConvertFrom-Json } catch { $null }
}

$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Afsluiten', $null, { [Windows.Forms.Application]::Exit() })

$icons = @{}
foreach ($key in $providers.Keys) {
    $n = New-Object Windows.Forms.NotifyIcon
    $n.ContextMenuStrip = $menu
    $n.Visible = $true
    $icons[$key] = $n
}

$script:tick = 0
function Update-Tray {
    foreach ($key in $providers.Keys) {
        $p = $providers[$key]
        if ($script:tick % $p.Every -eq 0) {
            $read = Read-Limits $key
            if ($read) { $p.State = @{ primary = $read.primary; secondary = $read.secondary; updated = Get-Date; stale = $false } }
            elseif ($p.State) { $p.State.stale = $true }
            else { $p.State = @{ stale = $true } }
        }
        $data = $p.State
        $percent = if ($data.primary) { [double]$data.primary.usedPercent } else { $null }
        $old = $icons[$key].Icon
        $icons[$key].Icon = New-LimitIcon $p.Mask $percent $data.stale
        if ($old) { [void][Win32.Icons]::DestroyIcon($old.Handle); $old.Dispose() }
        $parts = @(Format-Window $data.primary '5 uur'; Format-Window $data.secondary 'Week') | Where-Object { $_ }
        $body = if ($parts) { $parts -join "`n" } else { 'nog geen meting' }
        $title = $p.Label
        if ($data.stale -and $data.updated) { $title += ' - laatste meting ' + $data.updated.ToString('HH:mm') }
        elseif ($data.stale) { $title += ' - meting mislukt' }
        Set-TrayText $icons[$key] "$title`n$body"
    }
    $script:tick++
}

# Codex limits come from the local Codex app-server daemon, which does not survive a reboot.
# A pid file left over from before the reboot makes 'daemon start' fail with "Access is denied".
function Start-CodexDaemon {
    $dir = Join-Path $HOME '.codex\app-server-daemon'
    $exe = Join-Path $HOME '.codex\packages\app-server-daemon\current\bin\codex.exe'
    if (-not (Test-Path $exe)) { return }
    foreach ($name in 'daemon.pid', 'daemon-updater.pid') {
        $file = Join-Path $dir $name
        try { $id = (Get-Content $file -Raw | ConvertFrom-Json).pid } catch { continue }
        if (-not (Get-Process -Id $id -ErrorAction SilentlyContinue)) { Move-Item $file "$file.stale" -Force }
    }
    & $exe app-server daemon start *> $null
}

try { Start-CodexDaemon } catch { }

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 60000
$timer.add_Tick({ Update-Tray })
Update-Tray
$timer.Start()
[Windows.Forms.Application]::Run()
foreach ($n in $icons.Values) { $n.Visible = $false; $n.Dispose() }
