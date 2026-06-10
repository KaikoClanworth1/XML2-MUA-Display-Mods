<#
================================================================================
 MUA_Display_Mode.ps1  -  Marvel Ultimate Alliance (PC) display-mode switcher
================================================================================
 Adds windowed mode, borderless fullscreen, exclusive fullscreen, and any
 resolution to MUA. MUA runs through dgVoodoo2 (D3D9 wrapper) for clean window
 framing (centering / borderless / mouse), the same way the XML2 tool does.
 Run Install-dgVoodoo.ps1 first if dgVoodoo.conf isn't in the game folder.

 What it drives:
   1. libIGGfx.dll  -> builds a genuinely WINDOWED D3D9 device (Windowed=TRUE at
      D3DPRESENT_PARAMETERS+0x20). A windowed device is never minimized on focus loss.
   2. libIGDisplay.dll -> window style (titled / borderless) + neutralizes the
      "minimize/release display on focus loss" WM_ACTIVATE/WM_ACTIVATEAPP handlers.
   3. dgVoodoo.conf -> CenterAppWindow / WindowedAttributes / CaptureMouse etc.
      (centering, borderless framing, free cursor) -- replaces the old PowerShell
      window-mover and cursor patch.
   4. Registry HKCU\Software\Activision\Marvel Ultimate Alliance\Settings\Display\
      Resolution (REG_SZ "WxH") -> the render resolution.

 USAGE (run from the MUA folder, in PowerShell):
   .\MUA_Display_Mode.ps1 -Status
   .\MUA_Display_Mode.ps1 -Mode borderless                 # desktop-res borderless (recommended)
   .\MUA_Display_Mode.ps1 -Mode windowed                   # 1280x720 titled, centered window
   .\MUA_Display_Mode.ps1 -Mode windowed -Width 1600 -Height 900
   .\MUA_Display_Mode.ps1 -Mode fullscreen                 # stock exclusive fullscreen
   .\MUA_Display_Mode.ps1 -Revert                          # restore DLLs + dgVoodoo.conf from backup

 All edits are backed up to _resmod_backups\ and are fully reversible.
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
$DgVoodoo  = Join-Path $GameDir 'dgVoodoo.conf'
$BackupDir = Join-Path $GameDir '_resmod_backups'
$RegPath   = 'HKCU:\Software\Activision\Marvel Ultimate Alliance\Settings\Display'

# --- binary patch table (libIGGfx windowed device + libIGDisplay window style/focus) ---
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
    foreach ($f in @($Gfx, $Disp, $DgVoodoo)) {
        if (-not (Test-Path $f)) { continue }
        $name = Split-Path $f -Leaf
        $dst  = Join-Path $BackupDir "$name.orig"
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

function Write-TextAscii([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Set-DgVoodooAttr([string]$Key, [string]$Value) {
    if (-not (Test-Path $DgVoodoo)) { return }   # no dgVoodoo installed; skip silently
    $txt = Get-Content -Raw -Path $DgVoodoo
    $pattern = '(?m)^(' + [regex]::Escape($Key) + '\s*=).*$'
    if ($txt -notmatch $pattern) { return }
    $txt = [regex]::Replace($txt, $pattern, "`$1 $Value")
    Write-TextAscii $DgVoodoo $txt
}

function Apply-Mode([string]$mode) {
    Backup-Once
    # Retire the old cursor-flip patch (file 0x4021): dgVoodoo CaptureMouse handles the mouse now.
    if (Test-Path $Disp) {
        $b = [System.IO.File]::ReadAllBytes($Disp)
        if ($b[0x4021] -eq 0x01) { $b[0x4021] = 0x00; [System.IO.File]::WriteAllBytes($Disp, $b) }
    }
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
    # dgVoodoo framing (mirrors the XML2 tool)
    switch ($mode) {
        'windowed' {
            Set-DgVoodooAttr 'AppControlledScreenMode' 'true'
            Set-DgVoodooAttr 'FullScreenMode'          'false'
            Set-DgVoodooAttr 'WindowedAttributes'      ''
            Set-DgVoodooAttr 'FullscreenAttributes'    ''
            Set-DgVoodooAttr 'CenterAppWindow'         'true'
            Set-DgVoodooAttr 'CaptureMouse'            'false'
            Set-DgVoodooAttr 'FreeMouse'               'true'
        }
        'borderless' {
            Set-DgVoodooAttr 'AppControlledScreenMode' 'true'
            Set-DgVoodooAttr 'FullScreenMode'          'false'
            Set-DgVoodooAttr 'WindowedAttributes'      'borderless,fullscreensize'
            Set-DgVoodooAttr 'FullscreenAttributes'    ''
            Set-DgVoodooAttr 'CenterAppWindow'         'false'
            Set-DgVoodooAttr 'CaptureMouse'            'false'
            Set-DgVoodooAttr 'FreeMouse'               'true'
        }
        'fullscreen' {
            Set-DgVoodooAttr 'AppControlledScreenMode' 'true'
            Set-DgVoodooAttr 'FullScreenMode'          'false'
            Set-DgVoodooAttr 'WindowedAttributes'      ''
            Set-DgVoodooAttr 'FullscreenAttributes'    ''
            Set-DgVoodooAttr 'CenterAppWindow'         'false'
            Set-DgVoodooAttr 'CaptureMouse'            'true'
            Set-DgVoodooAttr 'FreeMouse'               'false'
        }
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
    if (Test-Path $DgVoodoo) {
        $d = Get-Content -Raw $DgVoodoo
        $cw = if ($d -match '(?m)^CenterAppWindow[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        $wa = if ($d -match '(?m)^WindowedAttributes[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        $cm = if ($d -match '(?m)^CaptureMouse[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        Write-Host ("  dgVoodoo    : CenterAppWindow={0}  CaptureMouse={1}  WindowedAttributes='{2}'" -f $cw,$cm,$wa)
    } else {
        Write-Host "  dgVoodoo    : NOT INSTALLED - run Install-dgVoodoo.ps1 for centering/borderless/mouse" -ForegroundColor DarkYellow
    }
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
    foreach ($f in @($Gfx, $Disp, $DgVoodoo)) {
        $name = Split-Path $f -Leaf; $src = Join-Path $BackupDir "$name.orig"
        if (Test-Path $src) { Copy-Item $src $f -Force; Write-Host "reverted $name from backup" -ForegroundColor Yellow }
    }
    Write-Host "Note: dgVoodoo DLLs remain installed (use Install-dgVoodoo.ps1 -Uninstall to remove). Registry Resolution unchanged." -ForegroundColor DarkGray
    Show-Status; return
}

if (-not $Mode) { Show-Status; return }

if (-not (Test-Path $DgVoodoo)) {
    Write-Host "dgVoodoo.conf not found in this folder." -ForegroundColor Yellow
    Write-Host "Run the installer first:  .\Install-dgVoodoo.ps1 -GamePath ""$GameDir""" -ForegroundColor Yellow
    Write-Host "(Continuing anyway - the binary patches will apply, but centering/borderless/mouse won't.)" -ForegroundColor DarkYellow
}

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
    'windowed'   { Write-Host "-> WINDOWED: a ${Width}x${Height} titled, centered window that stays open when unfocused." -ForegroundColor Green }
    'borderless' { Write-Host "-> BORDERLESS FULLSCREEN at ${Width}x${Height} (fills the monitor, Alt-Tab friendly)." -ForegroundColor Green }
    'fullscreen' { Write-Host "-> EXCLUSIVE FULLSCREEN at ${Width}x${Height} (stock; minimizes on Alt-Tab)." -ForegroundColor Green }
}
Write-Host ""
Show-Status
Write-Host ""
Write-Host "Launch Game.exe (or MUA.exe) to test. Revert anytime: .\MUA_Display_Mode.ps1 -Revert" -ForegroundColor Cyan
Write-Host "Avoid changing resolution via the in-game video menu while using a custom/windowed size." -ForegroundColor DarkGray
