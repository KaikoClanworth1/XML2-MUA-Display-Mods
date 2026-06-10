# XML2 Windowed / Borderless / Resolution mod

A small, fully‑reversible tool that adds **windowed mode**, **borderless fullscreen**,
**exclusive fullscreen**, and **any render resolution** to **X‑Men Legends II (PC, 2005)**.

The game itself is hardcoded to exclusive fullscreen at a fixed list of 4:3
resolutions and has no working windowed mode. This tool fixes that by driving the
three layers the game actually uses — without redistributing any game files.

> **This repo contains no game content.** It ships only a PowerShell script, three
> `.cmd` shortcuts, and docs. It edits *your own* installed copy (and backs up
> everything first). You must already own X‑Men Legends II and have it running.

---

## Requirements

- **X‑Men Legends II (PC)** installed and working.
- **dgVoodoo2** already set up in the game folder (the usual modern‑PC fix —
  `D3D8.dll`, `dgVoodoo.conf`, etc. next to `XMen2.exe`). Most modern installs and
  the marvelmods.com community builds already include it. This tool relies on it
  for the windowed/borderless framing.
- Windows PowerShell 5.1+ (built into Windows).

---

## Install

1. Download this repo (green **Code → Download ZIP**, or `git clone`).
2. Copy these files into your **X‑Men Legends II folder** (the one containing
   `XMen2.exe`):
   - `XML2_Display_Mode.ps1`
   - `Display - Windowed.cmd`
   - `Display - Borderless Fullscreen.cmd`
   - `Display - Exclusive Fullscreen.cmd`

That's it. (`research/` is optional — see [How it works](#how-it-works).)

---

## Use

**One‑click:** double‑click one of the shortcuts, then launch `XMen2.exe`:

| Shortcut | Result |
|---|---|
| `Display - Windowed.cmd` | A titled, centered, movable **1280×720 window** |
| `Display - Borderless Fullscreen.cmd` | Covers the whole monitor, **no border**, Alt‑Tab friendly |
| `Display - Exclusive Fullscreen.cmd` | True **exclusive fullscreen** (lowest latency, best for G‑Sync/FreeSync) |

**Custom resolution / advanced** (PowerShell, run from the game folder):

```powershell
.\XML2_Display_Mode.ps1 -Status                                   # show current settings
.\XML2_Display_Mode.ps1 -Mode windowed   -Width 1600 -Height 900  # any window size
.\XML2_Display_Mode.ps1 -Mode borderless -Width 2560 -Height 1440 # any borderless res
.\XML2_Display_Mode.ps1 -Mode fullscreen                          # native exclusive fullscreen
.\XML2_Display_Mode.ps1 -AddMenuResolutions 1920x1080,2560x1440   # add modes to the in-game menu
.\XML2_Display_Mode.ps1 -Revert                                   # undo everything
```

If PowerShell blocks the script, the `.cmd` shortcuts already bypass that; to run
the `.ps1` directly use `powershell -ExecutionPolicy Bypass -File .\XML2_Display_Mode.ps1 ...`.

---

## How it works

X‑Men Legends II runs on Raven's Alchemy engine and talks to **DirectX 8**, which is
wrapped to modern Direct3D 11 by **dgVoodoo2**. The render stack:

```
GPU + Windows (Direct3D 11)
      ▲
dgVoodoo2          ← the "D3D8.dll" in the game folder is dgVoodoo, not Microsoft's.
                     Translates the game's DirectX 8 calls to D3D11.
      ▲
XMen2.exe + Alchemy DLLs (libIGGfx, libIGDisplay, …)   ← the game
```

Three separate things are controlled at three different layers — the tool drives
all three so they stay consistent:

| What | Layer that owns it | Mechanism |
|---|---|---|
| **Render resolution** (both modes) | The **game** | Reads registry `HKCU\Software\Activision\X-Men Legends 2\Settings\Display\Resolution` (REG_SZ `"WxH"`) **unconditionally** at startup and renders natively at that size. dgVoodoo just passes the size through → sharp, **not** an upscale. |
| **Windowed vs fullscreen** | **dgVoodoo** | The game is hardcoded to demand exclusive fullscreen, so we set `[DirectX] AppControlledScreenMode=false` + `[General] FullScreenMode=false`, which makes dgVoodoo **override** the request and present in a desktop window. The game never knows. |
| **Title bar / border / centering** | a 4‑byte **patch** + dgVoodoo | The game builds its window with a borderless `WS_POPUP` style pinned to (0,0). For windowed mode the tool patches that style in `libIGDisplay.dll` to a titled, non‑resizable style and sets dgVoodoo `CenterAppWindow=true`. Borderless mode uses dgVoodoo `WindowedAttributes=borderless,fullscreensize`. |
| **Stay open when unfocused** | two 1‑byte **patches** | Because the game thinks it's fullscreen, its `WM_ACTIVATE`/`WM_ACTIVATEAPP` handlers minimize/release the display when you click away. The tool flips the two `je` guards (`74`→`EB`) in `libIGDisplay.dll` so those handlers do nothing — the window keeps running. Applied for windowed/borderless, restored for exclusive fullscreen. |

### Why this split?

- **dgVoodoo is essential for windowed/borderless** because the game refuses to be
  windowed on its own (the relevant instruction in `XMen2.exe` forces the fullscreen
  flag back on every launch). Only the wrapper underneath it can win that argument.
- **The game owns resolution**, not dgVoodoo. Setting the registry makes the game
  *render* natively at your chosen size. If you let dgVoodoo scale a 1024×768 image
  instead, you'd get a blurry upscale; this avoids that.
- **The DLL patch only adds a title bar**, which dgVoodoo can't do (it can remove a
  border but not add one). It's 4 bytes, guarded against offset drift, applied only
  in windowed mode, and reverted automatically for the other modes.

### Per‑mode summary

- **Windowed** — dgVoodoo forces a window + DLL patch adds the caption + dgVoodoo
  centers it + registry sets the (native) size.
- **Borderless** — dgVoodoo forces a window, strips the border, and stretches to the
  monitor; registry = native resolution.
- **Exclusive fullscreen** — dgVoodoo steps back (`AppControlledScreenMode=true`) and
  honors the game's own real fullscreen request (still DX8→DX11 underneath).

Widescreen renders correctly: the engine computes camera aspect and the 2D‑UI scale
from the live resolution, so true 16:9 is undistorted (Hor+) with a correct HUD.
(Ultrawide beyond 16:9 is untested and may shift some HUD art.)

Exact reverse‑engineered offsets are documented in
[`research/OFFSETS.md`](research/OFFSETS.md), and `research/pe_strings.py` is the
helper used to find/verify them.

---

## Caveats

- After setting a custom/windowed size, **don't change resolution from the in‑game
  Display Options menu** — picking a 4:3 entry rewrites the registry value. If that
  happens, just re‑run a `Display - *.cmd`.
- **Exclusive fullscreen** needs a resolution your GPU actually enumerates. If it
  black‑screens, use `-AddMenuResolutions` or pick **borderless**.
- The windowed window is intentionally **non‑resizable** (the engine has no
  resize handler; dragging the corner would garble the image).

---

## Uninstall / revert

```powershell
.\XML2_Display_Mode.ps1 -Revert
```

This restores `alchemy.ini`, `dgVoodoo.conf`, and `libIGDisplay.dll` from the
automatic backups in `_resmod_backups\`. The registry `Resolution` value is left as
last set (change it via any mode, or in the in‑game menu). You can also delete the
four files you copied in.

---

## License

The scripts and docs in this repo are released under the [MIT License](LICENSE).
This covers **only** the original tooling here — **not** X‑Men Legends II, the
Alchemy engine, or dgVoodoo2, which remain the property of their respective owners.
"X‑Men Legends" is a trademark of its respective owners; this is an unofficial,
non‑commercial fan tool with no affiliation or endorsement.
