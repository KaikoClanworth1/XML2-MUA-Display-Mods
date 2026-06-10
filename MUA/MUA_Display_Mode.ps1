<#
================================================================================
 MUA_Display_Mode.ps1  -  Marvel Ultimate Alliance (PC) display-mode switcher
================================================================================
 Adds windowed mode, borderless fullscreen, exclusive fullscreen, and any
 resolution to MUA. MUA runs NATIVE D3D9 (no dgVoodoo) - dgVoodoo was tried and
 it reintroduced focus-loss minimize + mouse-lock on MUA, so we keep it native.

 What it drives:
   1. libIGGfx.dll  -> builds a genuinely WINDOWED D3D9 device (Windowed=TRUE at
      D3DPRESENT_PARAMETERS+0x20). A windowed device is never minimized on focus loss.
   2. libIGDisplay.dll -> window style (titled / borderless), neutralizes the
      WM_ACTIVATE/WM_ACTIVATEAPP "minimize on focus loss" handlers, and keeps the
      OS cursor visible (ShowCursor hide->show).
   3. Window placement -> with -Launch, starts the game and sizes/positions the
      window (borderless = fill the screen, windowed = centered), since MUA has no
      wrapper to do it.
   4. Registry HKCU\Software\Activision\Marvel Ultimate Alliance\Settings\Display\
      Resolution (REG_SZ "WxH") -> the render resolution.

 USAGE (run from the MUA folder, in PowerShell):
   .\MUA_Display_Mode.ps1 -Status
   .\MUA_Display_Mode.ps1 -Mode borderless -Launch          # desktop-res borderless (recommended)
   .\MUA_Display_Mode.ps1 -Mode windowed   -Launch          # 1280x720 centered window
   .\MUA_Display_Mode.ps1 -Mode windowed   -Width 1600 -Height 900 -Launch
   .\MUA_Display_Mode.ps1 -Mode fullscreen                  # stock exclusive fullscreen
   .\MUA_Display_Mode.ps1 -Revert                           # restore DLLs from backup
 (Use -Launch so the script can size/center the window after the game opens.)
 All edits are backed up to _resmod_backups\ and are fully reversible.
================================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('windowed','borderless','fullscreen')]
    [string]$Mode,
    [int]$Width,
    [int]$Height,
    [switch]$Launch,
    [switch]$Status,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$GameDir   = $PSScriptRoot
$Exe       = Join-Path $GameDir 'Game.exe'
$Gfx       = Join-Path $GameDir 'libIGGfx.dll'
$Disp      = Join-Path $GameDir 'libIGDisplay.dll'
$BackupDir = Join-Path $GameDir '_resmod_backups'
$RegPath   = 'HKCU:\Software\Activision\Marvel Ultimate Alliance\Settings\Display'

function Get-Patches {
    @(
        @{ name='gfx: windowed D3D9 device (P1 skip mode-enum, refresh=0)'; file=$Gfx; off=0x5ada7
           stock=@(0x0F,0x84,0x1C,0x01,0x00,0x00); windowed=@(0xE9,0x1D,0x01,0x00,0x00,0x90) }
        @{ name='gfx: windowed D3D9 device (P2 Windowed=TRUE)';            file=$Gfx; off=0x5af01
           stock=@(0x8A,0x18);             windowed=@(0x32,0xDB) }
        @{ name='gfx: windowed D3D9 device (P3 windowed swap block)';      file=$Gfx; off=0x5af19
           stock=@(0x75,0x3C);             windowed=@(0x90,0x90) }
        @{ name='disp: window style (titled / borderless)';               file=$Disp; off=0x7893
           stock=@(0x00,0x00,0x00,0x85); windowed=@(0x00,0x00,0xCA,0x06); borderless=@(0x00,0x00,0x00,0x90) }
        @{ name='disp: stay-open (WM_ACTIVATE guard)';                    file=$Disp; off=0x5ebe
           stock=@(0x74,0x08);             windowed=@(0xEB,0x08) }
        @{ name='disp: stay-open (WM_ACTIVATEAPP guard)';                 file=$Disp; off=0x5ede
           stock=@(0x74,0x08);             windowed=@(0xEB,0x08) }
        @{ name='disp: OS cursor visible (ShowCursor hide->show)';        file=$Disp; off=0x4021
           stock=@(0x00);                  windowed=@(0x01) }
        @{ name='exe: free cursor (NOP ClipCursor confine)';              file=$Exe;  off=0x016120
           stock=@(0x52,0xFF,0x15,0x54,0x83,0x79,0x00); windowed=@(0x90,0x90,0x90,0x90,0x90,0x90,0x90) }
        @{ name='exe: cursor visible (device-init ShowCursor 0->1)';      file=$Exe;  off=0x31fd9b
           stock=@(0x00);                  windowed=@(0x01) }
        @{ name='exe: cursor visible (NOP startup ShowCursor hide #1)';   file=$Exe;  off=0x0193f3
           stock=@(0x53,0xFF,0xD6);        windowed=@(0x90,0x90,0x90) }
        @{ name='exe: cursor visible (NOP startup ShowCursor hide #2)';   file=$Exe;  off=0x019417
           stock=@(0x53,0xFF,0xD6);        windowed=@(0x90,0x90,0x90) }
    )
}

function Bytes-Eq($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    for ($i=0; $i -lt $a.Count; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    return $true
}
function Target-For($p, $mode) {
    switch ($mode) {
        'fullscreen' { return $p.stock }
        'windowed'   { return $p.windowed }
        'borderless' { if ($p.ContainsKey('borderless')) { return $p.borderless } else { return $p.windowed } }
    }
}

function Backup-Once {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    foreach ($f in @($Exe, $Gfx, $Disp)) {
        if (-not (Test-Path $f)) { continue }
        $name = Split-Path $f -Leaf; $dst = Join-Path $BackupDir "$name.orig"
        if (-not (Test-Path $dst)) { Copy-Item $f $dst; Write-Host "  backed up $name -> _resmod_backups\$name.orig" -ForegroundColor DarkGray }
    }
}

function Get-DesktopResolution {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        return @{ W = $b.Width; H = $b.Height }
    } catch { return @{ W = 1920; H = 1080 } }
}

function Apply-Mode([string]$mode) {
    Backup-Once
    foreach ($g in (Get-Patches | Group-Object { $_.file })) {
        $file = $g.Name; if (-not (Test-Path $file)) { Write-Host "  (missing $file - skipped)" -ForegroundColor DarkYellow; continue }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        foreach ($p in $g.Group) {
            $len = $p.stock.Count
            $cur = @(); for ($i=0; $i -lt $len; $i++) { $cur += $bytes[$p.off+$i] }
            $known = @($p.stock, $p.windowed); if ($p.ContainsKey('borderless')) { $known += ,$p.borderless }
            $ok = $false; foreach ($k in $known) { if (Bytes-Eq $cur $k) { $ok=$true; break } }
            if (-not $ok) { throw ("$(Split-Path $file -Leaf): unexpected bytes at 0x{0:x} - aborting (offset mismatch / different build?)" -f $p.off) }
            $tgt = Target-For $p $mode
            for ($i=0; $i -lt $len; $i++) { $bytes[$p.off+$i] = $tgt[$i] }
        }
        [System.IO.File]::WriteAllBytes($file, $bytes)
    }
}

function Set-Resolution([int]$W, [int]$H) {
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name 'Resolution' -Value ("{0}x{1}" -f $W, $H) -Type String
}

function Get-CurrentMode {
    if (-not (Test-Path $Disp)) { return 'unknown' }
    $b = [System.IO.File]::ReadAllBytes($Disp)
    if ($b[0x7896] -eq 0x90) { return 'borderless' }
    elseif ($b[0x7895] -eq 0xCA -and $b[0x7896] -eq 0x06) { return 'windowed' }
    elseif ($b[0x7896] -eq 0x85) { return 'fullscreen' }
    return 'unknown'
}

# MUA has no wrapper to place the window, so after launch we find it (class "igWin32WindowClass")
# and force the right size/position: borderless = fill the primary screen; windowed = centered.
function Position-GameWindow([string]$mode, [int]$W, [int]$H) {
    if ($mode -eq 'fullscreen' -or $mode -eq 'unknown') { return }
    if (-not ('MuaW32' -as [type])) {
        Add-Type @"
using System; using System.Runtime.InteropServices;
public class MuaW32 {
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
"@
    }
    $desk = Get-DesktopResolution
    Write-Host "Waiting for the game window to position it ($mode)..." -ForegroundColor DarkGray
    $hwnd = [IntPtr]::Zero
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        $hwnd = [MuaW32]::FindWindow('igWin32WindowClass', $null)
        if ($hwnd -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 400
    }
    if ($hwnd -eq [IntPtr]::Zero) { Write-Host "  (game window not found - not positioned; launch via this script to enable it)" -ForegroundColor DarkYellow; return }
    # MOVE only (no resize): the window is already created at the chosen resolution; resizing it would
    # desync the D3D9 back-buffer. SWP flags 0x45 = NOSIZE|NOZORDER|SHOWWINDOW.
    if ($mode -eq 'borderless') { $x = 0; $y = 0 }
    else {
        $x = [int](($desk.W - $W) / 2); $y = [int](($desk.H - $H) / 2)
        if ($x -lt 0) { $x = 0 }; if ($y -lt 0) { $y = 0 }
    }
    # Re-apply for a while to survive the game's own init repositioning (movies/legal screens).
    for ($n = 0; $n -lt 16; $n++) {
        [MuaW32]::SetWindowPos($hwnd, [IntPtr]::Zero, $x, $y, 0, 0, 0x45) | Out-Null
        Start-Sleep -Milliseconds 700
    }
    Write-Host "  game window positioned ($mode)." -ForegroundColor Green
}

function Start-Game {
    $exe = Join-Path $GameDir 'Game.exe'
    if (-not (Test-Path $exe)) { $exe = Join-Path $GameDir 'MUA.exe' }
    if (-not (Test-Path $exe)) { Write-Host "  (Game.exe/MUA.exe not found)" -ForegroundColor DarkYellow; return $false }
    Write-Host "Launching $(Split-Path $exe -Leaf)..." -ForegroundColor Cyan
    Start-Process -FilePath $exe -WorkingDirectory $GameDir | Out-Null
    return $true
}

function Show-Status {
    Write-Host "=== MUA display status (native D3D9) ===" -ForegroundColor Cyan
    if (Test-Path $RegPath) {
        $res = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue).Resolution
        Write-Host ("  registry    : Settings\Display\Resolution = {0}" -f $res)
    } else { Write-Host "  registry    : (Settings\Display absent)" }
    foreach ($g in (Get-Patches | Group-Object { $_.file })) {
        $file = $g.Name; if (-not (Test-Path $file)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        foreach ($p in $g.Group) {
            $len = $p.stock.Count; $cur=@(); for ($i=0;$i -lt $len;$i++){ $cur += $bytes[$p.off+$i] }
            $state = 'modified?'
            if (Bytes-Eq $cur $p.stock) { $state='stock (fullscreen)' }
            elseif (Bytes-Eq $cur $p.windowed) { $state='windowed' }
            elseif ($p.ContainsKey('borderless') -and (Bytes-Eq $cur $p.borderless)) { $state='borderless' }
            Write-Host ("  {0,-52} : {1}" -f $p.name, $state)
        }
    }
    $de = Get-DesktopResolution; Write-Host ("  desktop     : {0}x{1}" -f $de.W, $de.H) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
if ($Revert) {
    foreach ($f in @($Exe, $Gfx, $Disp)) {
        $name = Split-Path $f -Leaf; $src = Join-Path $BackupDir "$name.orig"
        if (Test-Path $src) { Copy-Item $src $f -Force; Write-Host "reverted $name from backup" -ForegroundColor Yellow }
    }
    Write-Host "Note: registry Resolution unchanged." -ForegroundColor DarkGray
    Show-Status; return
}

if (-not $Mode -and -not $Launch) { Show-Status; return }

if ($Mode) {
    $desk = Get-DesktopResolution
    if (-not $Width -or -not $Height) {
        switch ($Mode) { 'windowed' { $Width = 1280; $Height = 720 } default { $Width = $desk.W; $Height = $desk.H } }
    }
    Write-Host "Applying mode '$Mode' at ${Width}x${Height} ..." -ForegroundColor Cyan
    Apply-Mode $Mode
    Set-Resolution $Width $Height
    switch ($Mode) {
        'windowed'   { Write-Host "-> WINDOWED: ${Width}x${Height}, titled + centered (with -Launch), stays open when unfocused." -ForegroundColor Green }
        'borderless' { Write-Host "-> BORDERLESS FULLSCREEN: fills the screen (with -Launch), Alt-Tab friendly." -ForegroundColor Green }
        'fullscreen' { Write-Host "-> EXCLUSIVE FULLSCREEN at ${Width}x${Height} (stock; minimizes on Alt-Tab)." -ForegroundColor Green }
    }
    Write-Host ""; Show-Status; Write-Host ""
}

if ($Launch) {
    $m = if ($Mode) { $Mode } else { Get-CurrentMode }
    $de = Get-DesktopResolution
    $pw = if ($Width)  { $Width }  elseif ($m -eq 'windowed') { 1280 } else { $de.W }
    $ph = if ($Height) { $Height } elseif ($m -eq 'windowed') { 720 }  else { $de.H }
    if (Start-Game) { Position-GameWindow $m $pw $ph }
} else {
    Write-Host "Tip: add -Launch so the script can size/center the window after the game opens:" -ForegroundColor Cyan
    Write-Host "     .\MUA_Display_Mode.ps1 -Mode $($Mode) -Launch" -ForegroundColor DarkGray
    Write-Host "Revert anytime: .\MUA_Display_Mode.ps1 -Revert" -ForegroundColor Cyan
}
Write-Host "Avoid changing resolution via the in-game video menu while using a custom/windowed size." -ForegroundColor DarkGray
