<#
================================================================================
 Install-dgVoodoo.ps1  -  drop the bundled dgVoodoo2 wrapper into a game folder
================================================================================
 dgVoodoo2 (by Dege, freeware: http://dege.freeweb.hu/dgVoodoo2/) wraps legacy
 DirectX (DDraw / D3D8 / D3D9) onto modern D3D11/12. Putting its DLLs in a game's
 own folder makes the game load them instead of the system ones (local DLL override).

 This installs the bundled dgVoodoo2 v2.79.3 from .\dgVoodoo2\ into a target game
 folder so the display switchers can use dgVoodoo's clean windowed/borderless/center
 and mouse handling. Works for both X-Men Legends II (D3D8) and Marvel Ultimate
 Alliance (D3D9) — the same wrapper DLLs cover both.

 USAGE (PowerShell, from this repo folder):
   .\Install-dgVoodoo.ps1 -GamePath "C:\...\Games\Marvel Ultimate Alliance"
   .\Install-dgVoodoo.ps1 -GamePath "C:\...\Games\X-Men Legends II"
   .\Install-dgVoodoo.ps1 -GamePath "<folder>" -Uninstall    # remove the dgVoodoo files

 Existing files in the target are backed up to <game>\_resmod_backups\ first, and an
 existing dgVoodoo.conf is left untouched (the switcher manages it).
================================================================================
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

$SrcDir = Join-Path $PSScriptRoot 'dgVoodoo2'
$Wrappers = @('D3D8.dll','D3D9.dll','D3DImm.dll','DDraw.dll','dgVoodooCpl.exe','About dgVoodoo.txt')

# Resolve the target game folder.
if (-not $GamePath) {
    if ((Test-Path (Join-Path $PSScriptRoot 'XMen2.exe')) -or (Test-Path (Join-Path $PSScriptRoot 'Game.exe'))) {
        $GamePath = $PSScriptRoot
    } else {
        throw "Specify the game folder: .\Install-dgVoodoo.ps1 -GamePath ""<folder containing XMen2.exe or Game.exe>"""
    }
}
$GamePath = (Resolve-Path $GamePath).Path

# Identify the game (informational; the same DLLs cover D3D8 and D3D9).
$game = if (Test-Path (Join-Path $GamePath 'XMen2.exe')) { 'X-Men Legends II (D3D8)' }
        elseif (Test-Path (Join-Path $GamePath 'Game.exe')) { 'Marvel Ultimate Alliance (D3D9)' }
        else { 'UNKNOWN (no XMen2.exe / Game.exe found)' }

$BackupDir = Join-Path $GamePath '_resmod_backups'

if ($Uninstall) {
    Write-Host "Uninstalling dgVoodoo2 from: $GamePath" -ForegroundColor Cyan
    foreach ($f in @($Wrappers + 'dgVoodoo.conf')) {
        $dst = Join-Path $GamePath $f
        if (Test-Path $dst) {
            # restore a pre-install backup if we made one, else just delete
            $bak = Join-Path $BackupDir "$f.predgv"
            if (Test-Path $bak) { Copy-Item $bak $dst -Force; Write-Host "  restored $f from pre-install backup" -ForegroundColor Yellow }
            else { Remove-Item $dst -Force; Write-Host "  removed $f" -ForegroundColor Yellow }
        }
    }
    Write-Host "Done. (dgVoodoo.conf left as-is unless a pre-install backup existed.)" -ForegroundColor Green
    return
}

# --- install ---
if (-not (Test-Path $SrcDir)) { throw "Bundled dgVoodoo2 not found at: $SrcDir (run this from the repo folder)." }
Write-Host "Installing bundled dgVoodoo2 v2.79.3 into:" -ForegroundColor Cyan
Write-Host "  $GamePath" -ForegroundColor White
Write-Host "  detected game: $game" -ForegroundColor DarkGray
if ($game -like 'UNKNOWN*') { Write-Host "  WARNING: no game EXE detected here - double-check the folder." -ForegroundColor DarkYellow }

if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }

foreach ($f in $Wrappers) {
    $src = Join-Path $SrcDir $f
    $dst = Join-Path $GamePath $f
    if (-not (Test-Path $src)) { Write-Host "  (bundled $f missing - skipped)" -ForegroundColor DarkYellow; continue }
    if ((Test-Path $dst) -and -not (Test-Path (Join-Path $BackupDir "$f.predgv"))) {
        Copy-Item $dst (Join-Path $BackupDir "$f.predgv")   # one-time backup of whatever was there
    }
    Copy-Item $src $dst -Force
    Write-Host "  installed $f" -ForegroundColor Green
}

# Only lay down the base conf if the folder doesn't already have one (don't clobber a configured conf).
$confDst = Join-Path $GamePath 'dgVoodoo.conf'
if (Test-Path $confDst) {
    Write-Host "  kept existing dgVoodoo.conf (the display switcher manages it)" -ForegroundColor DarkGray
} else {
    Copy-Item (Join-Path $SrcDir 'dgVoodoo.conf') $confDst -Force
    Write-Host "  installed dgVoodoo.conf (pristine template)" -ForegroundColor Green
}

Write-Host ""
Write-Host "dgVoodoo2 installed. The game will now load dgVoodoo's wrapper instead of the" -ForegroundColor Cyan
Write-Host "system DirectX. Use the game's Display switcher to pick windowed/borderless/fullscreen." -ForegroundColor Cyan
Write-Host "Uninstall: .\Install-dgVoodoo.ps1 -GamePath ""$GamePath"" -Uninstall" -ForegroundColor DarkGray
