# Alchemy-engine display mods — X-Men Legends II & Marvel Ultimate Alliance

Small, fully-reversible tools that add **windowed mode**, **borderless fullscreen**,
**exclusive fullscreen**, and **any render resolution** to two Raven/Activision
Alchemy-engine action-RPGs:

| Game | Files | Renderer | dgVoodoo? |
|---|---|---|---|
| **X-Men Legends II** (2005) | [`XML2/`](XML2/) | D3D8 → dgVoodoo2 | required |
| **Marvel Ultimate Alliance** (2006) | [`MUA/`](MUA/) | native D3D9 | none |

Both games are hardcoded to exclusive fullscreen with no working windowed mode. The
core fix (shared by both) is to make the engine build a genuinely **windowed D3D
device** — an exclusive-fullscreen device gets minimized by Windows the moment it
loses focus; a windowed one does not — plus a small window-style patch for the title
bar / borderless frame. Everything is applied to *your own* installed copy and is
fully reversible (automatic backups in `_resmod_backups\`).

> **This repo contains no game content** — only PowerShell scripts, `.cmd` shortcuts,
> and docs. You must already own the games.

---

## Install & use

Copy your game's folder contents next to its EXE, then double-click a `Display - *.cmd`
(or run the `.ps1`). `-Status` shows the current state; `-Revert` undoes everything.

### X-Men Legends II — copy [`XML2/`](XML2/) next to `XMen2.exe`

Requires **dgVoodoo2** already in the game folder (the usual modern-PC fix; most
community builds include it).

| Shortcut | Result |
|---|---|
| `Display - Windowed.cmd` | Titled, centered, movable **1280×720** window |
| `Display - Borderless Fullscreen.cmd` | Fills the monitor, no border, Alt-Tab friendly |
| `Display - Exclusive Fullscreen.cmd` | True exclusive fullscreen |

```powershell
.\XML2_Display_Mode.ps1 -Status
.\XML2_Display_Mode.ps1 -Mode windowed -Width 1600 -Height 900
.\XML2_Display_Mode.ps1 -Mode borderless
.\XML2_Display_Mode.ps1 -AddMenuResolutions 1920x1080,2560x1440   # add modes to the in-game menu
.\XML2_Display_Mode.ps1 -Revert
```

### Marvel Ultimate Alliance — copy [`MUA/`](MUA/) next to `Game.exe`

Native D3D9, **no dgVoodoo needed**. Recommended: **borderless** (fills the screen;
avoids the no-wrapper centering/cursor caveats below).

| Shortcut | Result |
|---|---|
| `Display - Borderless Fullscreen.cmd` | Desktop-res borderless, Alt-Tab friendly *(recommended)* |
| `Display - Windowed.cmd` | Titled **1280×720** window *(spawns top-left — no centering without dgVoodoo)* |
| `Display - Exclusive Fullscreen.cmd` | Stock exclusive fullscreen |

```powershell
.\MUA_Display_Mode.ps1 -Status
.\MUA_Display_Mode.ps1 -Mode borderless
.\MUA_Display_Mode.ps1 -Mode windowed -Width 1600 -Height 900
.\MUA_Display_Mode.ps1 -Revert
```

If PowerShell blocks a script, the `.cmd` shortcuts already bypass that; or run
`powershell -ExecutionPolicy Bypass -File .\<script>.ps1 ...`.

---

## How it works

Both games run Raven's Alchemy engine. The **shared core fix:** the game is hardcoded
to build an **exclusive-fullscreen** D3D device, which Windows minimizes the instant it
loses focus. The tools patch the engine's `setDeviceParameters` so the device is created
**windowed** (`Windowed=TRUE`, refresh rate 0) on every create/reset — a genuinely
windowed device never minimizes. A separate `libIGDisplay.dll` patch sets the window
style (titled or borderless) and neutralizes the game's own "minimize on focus loss"
handlers. Resolution is the game's own native render, set via a registry value.

### X-Men Legends II (D3D8 + dgVoodoo2)

XML2 talks to **DirectX 8**, wrapped to D3D11 by **dgVoodoo2** (the `D3D8.dll` in the
folder is dgVoodoo, not Microsoft's).

| What | Owner | Mechanism |
|---|---|---|
| Render resolution | the game | registry `…\X-Men Legends 2\Settings\Display\Resolution` (REG_SZ), read at startup; native, not upscaled |
| Windowed device (no minimize) | `libIGGfx.dll` patch | force `D3DPRESENT_PARAMETERS.Windowed=TRUE` (D3D8 field at +0x1c) |
| Title bar / borderless / centering / mouse | `libIGDisplay.dll` patch + dgVoodoo | window-style patch + `CenterAppWindow` / `WindowedAttributes` / `CaptureMouse` |

Widescreen renders correctly (the engine computes aspect from the live resolution; true
16:9 is undistorted Hor+). Full offsets: [`research/OFFSETS-XML2.md`](research/OFFSETS-XML2.md).
*Quirks:* the cursor is hidden over the title bar (the game draws its own cursor); don't
change resolution from the in-game menu while on a custom size.

### Marvel Ultimate Alliance (native D3D9, no wrapper)

MUA is **native D3D9** with no dgVoodoo, so *everything* is game-side patches. The
windowed-device fix targets the real D3D9 present-params (`Windowed` at **+0x20**, vs
D3D8's +0x1c). Same `igWin32Window` window code as XML2 (different offsets); registry
key is `…\Marvel Ultimate Alliance\Settings\Display\Resolution`.

*Limitations (no dgVoodoo):* a bordered window spawns **top-left** (no centering) and
the OS cursor is free. **Borderless at desktop resolution** sidesteps both and is the
recommended mode. Avoid the in-game video menu while on a custom size. Full offsets:
[`research/OFFSETS-MUA.md`](research/OFFSETS-MUA.md).

---

## Uninstall / revert

Run `-Revert` from the game folder (`.\XML2_Display_Mode.ps1 -Revert` or
`.\MUA_Display_Mode.ps1 -Revert`). It restores the patched DLLs (and, for XML2,
`alchemy.ini` / `dgVoodoo.conf`) from `_resmod_backups\`. The registry `Resolution`
value is left as last set. You can also just delete the files you copied in.

---

## License

The scripts and docs here are released under the [MIT License](LICENSE). This covers
**only** the original tooling — **not** X-Men Legends II, Marvel Ultimate Alliance, the
Alchemy engine, or dgVoodoo2, which remain the property of their respective owners.
These are unofficial, non-commercial fan tools with no affiliation or endorsement.
