<#
================================================================================
 MUA_Display_Mode.ps1  -  Marvel Ultimate Alliance (PC) display-mode switcher
================================================================================
 Adds windowed mode, borderless fullscreen, exclusive fullscreen, and any
 resolution to MUA. MUA is NATIVE D3D9 (no dgVoodoo wrapper), so everything is
 done with small, reversible byte patches to the game's own DLLs plus the
 registry resolution value. Sister tool to XML2_Display_Mode.ps1.

 What it drives:
   1. libIGGfx.dll  -> builds a genuinely WINDOWED D3D9 device (Windowed=TRUE at
      D3DPRESENT_PARAMETERS+0x20, refresh rate 0). A windowed device is never
      minimized by Windows on focus loss (the XML2 lesson, applied to D3D9).
   2. libIGDisplay.dll -> window style (titled or borderless) + neutralizes the
      WM_ACTIVATE/WM_ACTIVATEAPP "minimize/release display on focus loss" path.
   3. Registry HKCU\Software\Activision\Marvel Ultimate Alliance\Settings\Display\
      Resolution (REG_SZ "WxH") -> the render resolution (read by Game.exe).

 USAGE (run from the MUA folder, in PowerShell):
   .\MUA_Display_Mode.ps1 -Status
   .\MUA_Display_Mode.ps1 -Mode borderless                 # desktop-res borderless (recommended)
   .\MUA_Display_Mode.ps1 -Mode windowed                   # 1280x720 titled window (spawns top-left)
   .\MUA_Display_Mode.ps1 -Mode windowed -Width 1600 -Height 900
   .\MUA_Display_Mode.ps1 -Mode fullscreen                 # stock exclusive fullscreen
   .\MUA_Display_Mode.ps1 -Revert                          # restore DLLs from backup

 All edits are backed up to _resmod_backups\ and are fully reversible.
 NOTE: MUA has no dgVoodoo, so a windowed (bordered) window spawns at the top-left
 (no centering) and the OS cursor is free. Borderless at desktop resolution avoids
 both (fills the screen) and is the recommended "looks fullscreen" mode.
================================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('windowed','borderless','fullscreen')]
    [string]$Mode,
    [int]$Width,
    [int]$Height,
    [switch]$Status,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$GameDir   = $PSScriptRoot
$Gfx       = Join-Path $GameDir 'libIGGfx.dll'
$Disp      = Join-Path $GameDir 'libIGDisplay.dll'
$BackupDir = Join-Path $GameDir '_resmod_backups'
$RegPath   = 'HKCU:\Software\Activision\Marvel Ultimate Alliance\Settings\Display'

# --- patch table: each site lists the bytes for stock(=fullscreen)/windowed/borderless ---
# borderless falls back to the windowed bytes when no 'borderless' key is given.
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
    foreach ($f in @($Gfx, $Disp)) {
        $name = Split-Path $f -Leaf
        $dst  = Join-Path $BackupDir "$name.orig"
        if ((Test-Path $f) -and -not (Test-Path $dst)) {
            Copy-Item $f $dst; Write-Host "  backed up $name -> _resmod_backups\$name.orig" -ForegroundColor DarkGray
        }
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
        $file  = $g.Name
        if (-not (Test-Path $file)) { Write-Host "  (missing $file - skipped)" -ForegroundColor DarkYellow; continue }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        foreach ($p in $g.Group) {
            $len = $p.stock.Count
            $cur = @(); for ($i=0; $i -lt $len; $i++) { $cur += $bytes[$p.off+$i] }
            $known = @($p.stock, $p.windowed); if ($p.ContainsKey('borderless')) { $known += ,$p.borderless }
            $ok = $false; foreach ($k in $known) { if (Bytes-Eq $cur $k) { $ok=$true; break } }
            if (-not $ok) { throw ("$(Split-Path $file -Leaf): unexpected bytes at 0x{0:x} - aborting (offset mismatch / different game build?)" -f $p.off) }
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

function Show-Status {
    Write-Host "=== MUA display status ===" -ForegroundColor Cyan
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
    $d = Get-DesktopResolution; Write-Host ("  desktop     : {0}x{1}" -f $d.W, $d.H) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
if ($Revert) {
    foreach ($f in @($Gfx, $Disp)) {
        $name = Split-Path $f -Leaf; $src = Join-Path $BackupDir "$name.orig"
        if (Test-Path $src) { Copy-Item $src $f -Force; Write-Host "reverted $name from backup" -ForegroundColor Yellow }
        else { Write-Host "no backup for $name" -ForegroundColor DarkYellow }
    }
    Write-Host "Note: registry Resolution was NOT reverted (set a mode to change it, or edit it in-game)." -ForegroundColor DarkGray
    Show-Status; return
}

if (-not $Mode) { Show-Status; return }

$desk = Get-DesktopResolution
if (-not $Width -or -not $Height) {
    switch ($Mode) {
        'windowed' { $Width = 1280;    $Height = 720 }
        default    { $Width = $desk.W; $Height = $desk.H }
    }
}

Write-Host "Applying mode '$Mode' at ${Width}x${Height} ..." -ForegroundColor Cyan
Apply-Mode $Mode
Set-Resolution $Width $Height

switch ($Mode) {
    'windowed'   { Write-Host "-> WINDOWED: a ${Width}x${Height} titled window that stays open when unfocused." -ForegroundColor Green
                   Write-Host "   (No dgVoodoo on MUA: the window spawns at the top-left, not centered.)" -ForegroundColor DarkYellow }
    'borderless' { Write-Host "-> BORDERLESS FULLSCREEN at ${Width}x${Height} (fills the monitor, Alt-Tab friendly)." -ForegroundColor Green }
    'fullscreen' { Write-Host "-> EXCLUSIVE FULLSCREEN at ${Width}x${Height} (stock; minimizes on Alt-Tab)." -ForegroundColor Green }
}
Write-Host ""
Show-Status
Write-Host ""
Write-Host "Launch Game.exe (or MUA.exe) to test. Revert anytime: .\MUA_Display_Mode.ps1 -Revert" -ForegroundColor Cyan
Write-Host "Avoid changing resolution via the in-game video menu while using a custom/windowed size." -ForegroundColor DarkGray
