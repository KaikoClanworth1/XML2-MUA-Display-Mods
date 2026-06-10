<#
================================================================================
 XML2_Display_Mode.ps1  -  X-Men Legends II (PC) display-mode switcher
================================================================================
 Makes XML2 support: windowed mode, borderless fullscreen, exclusive fullscreen,
 and ANY resolution - by driving the three layers the game actually uses:

   1. alchemy.ini  [Viewer] fullScreen   -> screen mode (true=fullscreen, false=windowed)
   2. Registry     HKCU\Software\Activision\X-Men Legends 2\Settings\Display\Resolution
                   (REG_SZ "WxH")  -> the render resolution. The game reads this
                   UNCONDITIONALLY at startup (sscanf "%dx%d") for BOTH modes, so
                   this is the real resolution lever (verified at XMen2.exe 0x61bf80).
   3. dgVoodoo.conf [GeneralExt] WindowedAttributes / FullscreenAttributes
                   -> borderless framing (dgVoodoo2 sits under the game's D3D8).

 The 3D camera aspect and 2D-UI scale are computed from the live resolution
 (XMen2.exe 0x5fad82 / 0x5fad70), so true 16:9 renders undistorted (Hor+).

 USAGE (run from the game folder, in PowerShell):
   .\XML2_Display_Mode.ps1 -Status
   .\XML2_Display_Mode.ps1 -Mode borderless                 # native desktop res, borderless fullscreen
   .\XML2_Display_Mode.ps1 -Mode fullscreen                 # exclusive fullscreen, native res
   .\XML2_Display_Mode.ps1 -Mode windowed                   # 1280x720 window (default)
   .\XML2_Display_Mode.ps1 -Mode windowed -Width 1600 -Height 900
   .\XML2_Display_Mode.ps1 -Mode borderless -Width 2560 -Height 1440
   .\XML2_Display_Mode.ps1 -AddMenuResolutions 1920x1080,2560x1440   # add modes to the in-game menu
   .\XML2_Display_Mode.ps1 -Revert                          # restore alchemy.ini + dgVoodoo.conf backups

 All edits are backed up to _resmod_backups\ and are fully reversible.
================================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('windowed','borderless','fullscreen')]
    [string]$Mode,
    [int]$Width,
    [int]$Height,
    [string]$AddMenuResolutions,
    [switch]$Status,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$GameDir   = $PSScriptRoot
$Alchemy   = Join-Path $GameDir 'alchemy.ini'
$DgVoodoo  = Join-Path $GameDir 'dgVoodoo.conf'
$BackupDir = Join-Path $GameDir '_resmod_backups'
$RegPath   = 'HKCU:\Software\Activision\X-Men Legends 2\Settings\Display'

function Write-TextAscii([string]$Path, [string]$Content) {
    # PS 5.1 Out-File/Set-Content default to UTF-16; these .ini/.conf files must stay ASCII.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Backup-Once {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    foreach ($f in @($Alchemy, $DgVoodoo)) {
        $name = Split-Path $f -Leaf
        $dst  = Join-Path $BackupDir "$name.orig"
        if ((Test-Path $f) -and -not (Test-Path $dst)) {
            Copy-Item $f $dst
            Write-Host "  backed up $name -> _resmod_backups\$name.orig" -ForegroundColor DarkGray
        }
    }
}

function Get-DesktopResolution {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        return @{ W = $b.Width; H = $b.Height }
    } catch {
        return @{ W = 1920; H = 1080 }   # safe fallback
    }
}

function Set-AlchemyFullScreen([bool]$FullScreen, [int]$W, [int]$H) {
    $txt = Get-Content -Raw -Path $Alchemy
    $val = if ($FullScreen) { 'true' } else { 'false' }
    $txt = [regex]::Replace($txt, '(?m)^(\s*fullScreen\s*=\s*).*$', "fullScreen = $val")
    # width/height are only fallbacks, but keep them consistent so a registry-read failure still lands right.
    $txt = [regex]::Replace($txt, '(?m)^(\s*width\s*=\s*)\d+.*$',  "width = $W")
    $txt = [regex]::Replace($txt, '(?m)^(\s*height\s*=\s*)\d+.*$', "height = $H")
    Write-TextAscii $Alchemy $txt
}

function Set-DgVoodooAttr([string]$Key, [string]$Value) {
    # Replaces a single "Key   = ..." setting line in [GeneralExt]/[DirectXExt]; leaves comments (";  Key:") intact.
    $txt = Get-Content -Raw -Path $DgVoodoo
    $pattern = '(?m)^(' + [regex]::Escape($Key) + '\s*=).*$'
    if ($txt -notmatch $pattern) { throw "dgVoodoo.conf: setting line '$Key =' not found" }
    $txt = [regex]::Replace($txt, $pattern, "`$1 $Value")
    Write-TextAscii $DgVoodoo $txt
}

function Set-Resolution([int]$W, [int]$H) {
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPath -Name 'Resolution' -Value ("{0}x{1}" -f $W, $H) -Type String
    # Suppress the in-game "keep this resolution?" countdown so a direct change applies cleanly.
    try { Set-ItemProperty -Path $RegPath -Name 'WarningRes' -Value 0 -Type DWord } catch {}
}

# The game hardwires its fullscreen flag, so it always builds its window with the FULLSCREEN style
# (WS_POPUP, no caption, pinned to 0,0). For a real titled window we patch that style immediate in
# libIGDisplay.dll (file 0x5809: 0x85000000) to a bordered, non-resizable overlapped style (0x06CA0000).
# 4 bytes, reversible, guarded against offset drift. $Bordered=$false restores the original.
function Set-WindowBorder([bool]$Bordered) {
    $dll = Join-Path $GameDir 'libIGDisplay.dll'
    if (-not (Test-Path $dll)) { Write-Host "  (libIGDisplay.dll not found - skipping border patch)" -ForegroundColor DarkYellow; return }
    $off = 0x5809
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    $dst = Join-Path $BackupDir 'libIGDisplay.dll.orig'
    if (-not (Test-Path $dst)) { Copy-Item $dll $dst; Write-Host "  backed up libIGDisplay.dll -> _resmod_backups\libIGDisplay.dll.orig" -ForegroundColor DarkGray }
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    $isOrig = ($bytes[$off] -eq 0x00 -and $bytes[$off+1] -eq 0x00 -and $bytes[$off+2] -eq 0x00 -and $bytes[$off+3] -eq 0x85)
    $isBord = ($bytes[$off] -eq 0x00 -and $bytes[$off+1] -eq 0x00 -and $bytes[$off+2] -eq 0xCA -and $bytes[$off+3] -eq 0x06)
    if (-not ($isOrig -or $isBord)) {
        throw ("libIGDisplay.dll: unexpected bytes at 0x{0:x} ({1:x2} {2:x2} {3:x2} {4:x2}) - aborting style patch" -f $off,$bytes[$off],$bytes[$off+1],$bytes[$off+2],$bytes[$off+3])
    }
    $target = if ($Bordered) { @(0x00,0x00,0xCA,0x06) } else { @(0x00,0x00,0x00,0x85) }
    for ($i=0; $i -lt 4; $i++) { $bytes[$off+$i] = $target[$i] }
    [System.IO.File]::WriteAllBytes($dll, $bytes)
}

function Show-Status {
    Write-Host "=== XML2 display status ===" -ForegroundColor Cyan
    if (Test-Path $Alchemy) {
        $a = Get-Content -Raw $Alchemy
        $fs = if ($a -match '(?m)^\s*fullScreen\s*=\s*(\S+)') { $Matches[1] } else { '?' }
        $w  = if ($a -match '(?m)^\s*width\s*=\s*(\d+)')      { $Matches[1] } else { '?' }
        $h  = if ($a -match '(?m)^\s*height\s*=\s*(\d+)')     { $Matches[1] } else { '?' }
        Write-Host ("  alchemy.ini : fullScreen={0}  width={1} height={2} (fallback)" -f $fs,$w,$h)
    }
    if (Test-Path $RegPath) {
        $res = (Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue).Resolution
        Write-Host ("  registry    : Settings\Display\Resolution = {0}  (the ACTIVE render resolution)" -f $res)
    } else {
        Write-Host "  registry    : Settings\Display absent - game falls back to alchemy.ini size"
    }
    if (Test-Path $DgVoodoo) {
        $d = Get-Content -Raw $DgVoodoo
        $ac = if ($d -match '(?m)^AppControlledScreenMode[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        $fm = if ($d -match '(?m)^FullScreenMode[ \t]*=[ \t]*([^\r\n]*)')          { $Matches[1].Trim() } else { '?' }
        $wa = if ($d -match '(?m)^WindowedAttributes[ \t]*=[ \t]*([^\r\n]*)')   { $Matches[1].Trim() } else { '?' }
        $fa = if ($d -match '(?m)^FullscreenAttributes[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        $ex = if ($d -match '(?m)^ExtraEnumeratedResolutions[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        $cw = if ($d -match '(?m)^CenterAppWindow[ \t]*=[ \t]*([^\r\n]*)') { $Matches[1].Trim() } else { '?' }
        Write-Host ("  dgVoodoo    : AppControlledScreenMode={0}  FullScreenMode={1}  (false/false = forced window)" -f $ac,$fm)
        Write-Host ("                WindowedAttributes='{0}'  FullscreenAttributes='{1}'  CenterAppWindow={2}" -f $wa,$fa,$cw)
        Write-Host ("                ExtraEnumeratedResolutions='{0}'" -f $ex)
    }
    $dll = Join-Path $GameDir 'libIGDisplay.dll'
    if (Test-Path $dll) {
        $b = [System.IO.File]::ReadAllBytes($dll)
        $style = if ($b[0x580b] -eq 0xCA -and $b[0x580c] -eq 0x06) { 'bordered/titled (0x06CA0000)' } elseif ($b[0x580c] -eq 0x85) { 'borderless WS_POPUP (0x85000000, stock)' } else { 'unknown' }
        Write-Host ("  libIGDisplay: window style = {0}" -f $style)
    }
    $desk = Get-DesktopResolution
    Write-Host ("  desktop     : {0}x{1}" -f $desk.W, $desk.H) -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
if ($Revert) {
    foreach ($f in @($Alchemy, $DgVoodoo, (Join-Path $GameDir 'libIGDisplay.dll'))) {
        $name = Split-Path $f -Leaf
        $src  = Join-Path $BackupDir "$name.orig"
        if (Test-Path $src) { Copy-Item $src $f -Force; Write-Host "reverted $name from backup" -ForegroundColor Yellow }
        else { Write-Host "no backup for $name" -ForegroundColor DarkYellow }
    }
    Write-Host "Note: registry Resolution was NOT reverted (set a mode to change it, or edit it in-game)." -ForegroundColor DarkGray
    Show-Status; return
}

if ($AddMenuResolutions) {
    Backup-Once
    Set-DgVoodooAttr 'ExtraEnumeratedResolutions' $AddMenuResolutions
    Write-Host "Added to in-game menu enumeration: $AddMenuResolutions" -ForegroundColor Green
    Write-Host "(These now appear in the in-game Display Options resolution list.)"
    if (-not $Mode) { Show-Status; return }
}

if (-not $Mode) { Show-Status; return }

# Resolve target resolution
$desk = Get-DesktopResolution
if (-not $Width -or -not $Height) {
    switch ($Mode) {
        'windowed'   { $Width = 1280;      $Height = 720 }       # comfortable sub-desktop window
        default      { $Width = $desk.W;   $Height = $desk.H }   # borderless/fullscreen -> native
    }
}

Write-Host "Applying mode '$Mode' at ${Width}x${Height} ..." -ForegroundColor Cyan
Backup-Once

switch ($Mode) {
    'windowed' {
        # The game hardcodes fullscreen (XMen2.exe 0x5facb1 forces the flag to 1) and ignores
        # alchemy.ini fullScreen, so we make dgVoodoo OVERRIDE the screen mode and force a window.
        Set-AlchemyFullScreen $false $Width $Height       # harmless; kept consistent
        Set-DgVoodooAttr 'AppControlledScreenMode' 'false' # dgVoodoo decides the mode, not the game
        Set-DgVoodooAttr 'FullScreenMode'          'false' # ...and that mode is WINDOWED
        Set-DgVoodooAttr 'WindowedAttributes'      ''       # let the (now bordered) game window show its caption
        Set-DgVoodooAttr 'FullscreenAttributes'    'fake'   # harmless
        Set-DgVoodooAttr 'CenterAppWindow'         'true'   # un-stick from top-left (game hardcodes pos 0,0)
        Set-WindowBorder $true                              # patch libIGDisplay style -> titled, movable window
        Set-Resolution $Width $Height
        Write-Host "-> WINDOWED: a ${Width}x${Height} titled, centered, movable window." -ForegroundColor Green
        if ($Width -ge $desk.W -or $Height -ge $desk.H) {
            Write-Host "   (Tip: window is at/above desktop size; use a smaller -Width/-Height or 'borderless' instead.)" -ForegroundColor DarkYellow
        }
    }
    'borderless' {
        # Force windowed under the hood, then present it borderless at full screen size.
        Set-AlchemyFullScreen $true $Width $Height
        Set-DgVoodooAttr 'AppControlledScreenMode' 'false'
        Set-DgVoodooAttr 'FullScreenMode'          'false'
        Set-DgVoodooAttr 'WindowedAttributes'      'borderless,fullscreensize'  # no border, fills monitor
        Set-DgVoodooAttr 'FullscreenAttributes'    'fake'
        Set-DgVoodooAttr 'CenterAppWindow'         'false'
        Set-WindowBorder $false                             # restore borderless game window style
        Set-Resolution $Width $Height
        Write-Host "-> BORDERLESS FULLSCREEN at ${Width}x${Height} (Alt-Tab friendly, no exclusive mode)." -ForegroundColor Green
    }
    'fullscreen' {
        # Let the game drive a real exclusive-fullscreen request and have dgVoodoo honor it.
        Set-AlchemyFullScreen $true $Width $Height
        Set-DgVoodooAttr 'AppControlledScreenMode' 'true'   # game controls -> real exclusive fullscreen
        Set-DgVoodooAttr 'FullScreenMode'          'false'
        Set-DgVoodooAttr 'FullscreenAttributes'    ''        # real exclusive (not fake)
        Set-DgVoodooAttr 'WindowedAttributes'      ''
        Set-DgVoodooAttr 'CenterAppWindow'         'false'
        Set-WindowBorder $false                             # restore borderless WS_POPUP for exclusive FS
        Set-Resolution $Width $Height
        Write-Host "-> EXCLUSIVE FULLSCREEN at ${Width}x${Height} (must be a mode your GPU enumerates)." -ForegroundColor Green
        Write-Host "   (If it black-screens, that resolution isn't enumerated - use -AddMenuResolutions or 'borderless'.)" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Show-Status
Write-Host ""
Write-Host "Launch XMen2.exe (or XMen2_LAA.exe) to test. Revert anytime: .\XML2_Display_Mode.ps1 -Revert" -ForegroundColor Cyan
Write-Host "Avoid changing resolution via the in-game Display Options menu while using a custom/windowed size." -ForegroundColor DarkGray
