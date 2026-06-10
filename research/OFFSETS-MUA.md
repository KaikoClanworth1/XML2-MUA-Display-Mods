# Reverse-engineering notes — Marvel Ultimate Alliance (MUA) display handling

MUA is the sister game to X-Men Legends 2 on the same Alchemy engine, but **native
Direct3D 9** (no dgVoodoo wrapper) and ~1 year newer, so the offsets differ. The
binaries here retain full C++ export symbols, so every target was resolved from the
export table. Offsets verified byte-for-byte against the shipped DLLs (image base
`0x10000000`; file offset = VA − 0x10000000 for the `.text` regions used here).

## Windowed D3D9 device (libIGGfx.dll) — the "no minimize on focus loss" fix

Same lesson as XML2: an **exclusive-fullscreen** device is minimized by Windows on
focus loss. The fix forces a **windowed** device. The D3DPRESENT_PARAMETERS buffer
lives at `igDxDevice+0x18` and is the exact buffer passed to `IDirect3D9::CreateDevice`
(`call [ecx+0x40]` = vtable slot 16, at `0x1005e331` inside `igDxDevice::createDevice`).

D3D9 field offsets (note **Windowed is at +0x20**, not D3D8's +0x1c):
`Windowed = igDxDevice+0x38 = present+0x20`; `FullScreen_RefreshRateInHz = +0x48 = present+0x30`.
The mode flag is the byte at `*(igDxDevice+0xa0)` (MUA's analog of XML2's `obj+0x180`).

In `igDxDevice::setDeviceParameters` (`0x1005ac60`):
```
0x1005ada0  cmp byte [edx],0 ; je 0x1005aec9   ; flag==0 -> windowed branch (refresh stays 0)
0x1005af01  mov bl,[eax]; test bl,bl; sete dl; mov [esi+0x38],edx   ; Windowed = (flag==0)
0x1005af16  cmp byte [eax],0 ; jne 0x1005af57  ; skip windowed swap-block when fullscreen
```

| Patch | File offset | Original | Patched | Effect |
|---|---|---|---|---|
| P1 (required) | `0x5ada7` | `0F 84 1C 01 00 00` | `E9 1D 01 00 00 90` | force the `je` to an unconditional `jmp 0x1005aec9` → always take the windowed branch; skips the mode-enum loop (the only writer of refresh rate), so refresh stays **0**. D3D9 requires refresh=0 for a windowed device or `CreateDevice` fails `D3DERR_INVALIDCALL`. |
| P2 (essential) | `0x5af01` | `8A 18` | `32 DB` | `mov bl,[eax]` → `xor bl,bl`, so `sete dl` makes **`Windowed = TRUE`** unconditionally. |
| P3 (hardening) | `0x5af19` | `75 3C` | `90 90` | NOP the `jne` so the windowed swap-block (SwapEffect, PresentationInterval) always runs. |

## Window style + stay-open (libIGDisplay.dll)

`igWin32Window` is the same class as XML2; `_fullScreen` is the byte at **obj+0x46**
(confirmed by `getFullScreenState@0x10003640 = mov al,[ecx+0x46]; ret`). Because the
flag stays set, the window is built with the fullscreen `WS_POPUP` style at (0,0):

```
0x1000788d  je 0x1000789f                      ; flag==0 -> windowed style
0x1000788f  mov [esp+0x10], 0x85000000         ; FS style (WS_POPUP)  <- dword at file 0x7893
0x10007897  mov [esi+0x30],ebx ; mov [esi+0x34],ebx  ; X=0, Y=0 (top-left)
0x1000789f  mov [esp+0x10], 0x06CF0000         ; (unused) windowed style
```

| Patch | File offset | Original | Patched | Effect |
|---|---|---|---|---|
| Title bar | `0x7893` (dword) | `00 00 00 85` | `00 00 CA 06` | `0x85000000` → `0x06CA0000` (WS_CAPTION\|WS_SYSMENU\|WS_MINIMIZEBOX\|WS_CLIPSIBLINGS\|WS_CLIPCHILDREN) = titled, non-resizable window. |
| Borderless | `0x7893` (dword) | `00 00 00 85` | `00 00 00 90` | `0x90000000` (WS_POPUP\|WS_VISIBLE) = borderless; pair with desktop resolution to fill the screen. |
| Stay-open (activate) | `0x5ebe` | `74 08` | `EB 08` | WM_ACTIVATE worker (`0x10005eb0`): flip `je`→`jmp` so it never calls `vtbl[+0x42c]` (reacquire exclusive display). |
| Stay-open (deactivate) | `0x5ede` | `74 08` | `EB 08` | WM_ACTIVATEAPP worker (`0x10005ed0`): flip `je`→`jmp` so it never calls `vtbl[+0x430]` (minimize/release display on focus loss). |

## Resolution + screen mode

- Resolution = registry `HKCU\Software\Activision\Marvel Ultimate Alliance\Settings\Display\Resolution`
  (REG_SZ "WxH"). Read by `Game.exe` via `sscanf("%dx%d")` (`0x6da18a`); key built from
  `"Software\%s\%s"` + `"Activision"` + `"Marvel Ultimate Alliance"` (`0x74ea20`).
- **No screen-mode source patch needed.** There is no INI and no registry screen-mode
  value; the engine `fullScreen` config param defaults to 0/windowed and `forceFullScreen`
  (GFX config) defaults to 0. The exclusive device is produced downstream, which is exactly
  what the libIGGfx/libIGDisplay patches override.

## Cursor — Game.exe (NOT a wrapper)

MUA stays **native D3D9** (dgVoodoo was tried and it *reintroduced* the focus-loss minimize +
mouse-lock, so it is NOT used for MUA). The cursor behavior the user sees is all in **Game.exe**,
which imports `ClipCursor`/`ShowCursor`/`SetCapture` and manages the cursor itself — the
`libIGDisplay` patches can't reach it. Patches (file = VA − 0x400000):

| Purpose | VA | File off | Original | Patched |
|---|---|---|---|---|
| **Free the cursor** — NOP the per-frame `push edx; call ClipCursor(&rect)` confine (input loop `0x416010`) | `0x416120` | `0x16120` | `52 FF 15 54 83 79 00` | `90 ×7` |
| **Show cursor** — device-init `ShowCursor(0)`→`(1)` | `0x71fd9a` | `0x31fd9b` | `00` | `01` |
| **Show cursor** — NOP startup `push ebx; call esi`(=ShowCursor 0) | `0x4193f3` | `0x193f3` | `53 FF D6` | `90 90 90` |
| **Show cursor** — NOP startup `push ebx; call esi` | `0x419417` | `0x19417` | `53 FF D6` | `90 90 90` |

Left intact on purpose: `SetCapture` (`0x71ddac`, per-click drag), the inactive-branch
`ClipCursor(NULL)` release (`0x41609e`), and `ShowCursor(1)` before error dialogs.

**Minimize** is *not* a Game.exe call (its only `ShowWindow` is `SW_RESTORE` single-instance focus);
it's D3D9 exclusive-fullscreen auto-minimize, which the **windowed-device patch above** prevents.

## Window placement (no wrapper)

With `-Launch`, the switcher finds the window (class `igWin32WindowClass`) and **moves** it
(borderless → top-left/fill, windowed → centered) — move only, never resize, to avoid desyncing
the D3D9 back-buffer.

Still flagged for runtime testing: a `Reset()` or the in-game resolution menu
(`changeResolutionAccepted/Refused`) may rebuild the device — set resolution via the switcher
and avoid the in-game video menu.
