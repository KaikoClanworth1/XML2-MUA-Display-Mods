# Reverse‑engineering notes — XML2 display handling

These are the verified facts behind the mod. Offsets are from a common
**X‑Men Legends II PC** build (`XMen2.exe`, 3,129,344 bytes; Alchemy engine DLLs).
Other builds may differ — the script's one DLL patch is **guarded**: it checks the
expected bytes first and aborts if they don't match, so it can't corrupt a different
build.

`pe_strings.py` (in this folder) is the helper used to find/verify these
(`strings`, `grep`, `xref`, `imports`, `disasm`, `at`). Image bases:
`XMen2.exe = 0x00400000`, the `libIG*.dll` engine libs `= 0x10000000`.

## Resolution (owned by the game)

- **`XMen2.exe 0x61bf80`** — reads the resolution and `sscanf("%dx%d")` parses it into
  width/height. Called **unconditionally** from `0x5fac45` (no fullscreen gate), so it
  governs the render size in *both* windowed and fullscreen.
- Source = Windows registry, REG_SZ string `"WxH"`:
  `HKCU\Software\Activision\X-Men Legends 2\Settings\Display\Resolution`
  (key path built from `"Software\%s\%s"` + company `"Activision"` + product
  `"X-Men Legends 2"`). `alchemy.ini [Viewer] width/height` are only a fallback.
- The result lands in render globals `0xa09ffc` (width) / `0xa0a000` (height).

## Screen mode (the game hardcodes fullscreen)

- **`XMen2.exe 0x5646a0`** reads `alchemy.ini [Viewer] fullScreen` into the
  viewer‑config singleton, **but**
- **`XMen2.exe 0x5facb1`** does `mov byte [edi+4], 1` — it forces that fullscreen flag
  back to `1` every launch, so `alchemy.ini fullScreen=false` is ignored.
  (Tested: the game still goes fullscreen.) There is no registry mode flag and no
  `-window` command‑line switch — only the unused Alchemy startup dialog
  (`igWin32WindowSetupDialog`, "&Windowed mode") in `libIGDisplay.dll`.
- ⇒ Windowed has to be forced one layer down, in **dgVoodoo2**:
  `[DirectX] AppControlledScreenMode=false` + `[General] FullScreenMode=false`.

## Back‑buffer sizing

- **`libIGGfx.dll 0x1002cfe0`** `setDeviceParameters`: the `D3DPRESENT_PARAMETERS` is
  zeroed (`rep stosd`), then `Windowed = (isFullScreen==0)`. In the **windowed** branch
  `BackBufferWidth/Height` are never written (stay 0 → D3D8 adopts the window client
  size = native render). The **fullscreen** branch copies an enumerated adapter mode in
  (so exclusive fullscreen needs the resolution to be enumerated).

## Window style (what the mod patches)

`libIGDisplay.dll`, branch at **VA `0x100057ff`**:

```
0x100057ff  mov cl, [esi+0x46]      ; the (forced-on) fullscreen flag
0x10005806  je  0x1000581a          ; ==0 -> windowed
0x10005808  mov edi, 0x85000000     ; FULLSCREEN style = WS_POPUP (no caption)  <-- taken
0x1000580d  mov [esi+0x30], 0       ; X = 0   } window pinned to top-left
0x10005810  mov [esi+0x34], 0       ; Y = 0   }
0x1000581a  mov edi, 0x06CF0000     ; windowed style (never reached: flag is forced on)
```

Because the flag is forced on, the game always builds a **borderless `WS_POPUP` window
at (0,0)** — which is why a dgVoodoo‑forced window appears borderless in the top‑left.

**Patch #1 (title bar):** file offset **`0x5809`** (the `0x85000000` immediate),
`00 00 00 85` → `00 00 CA 06` (`0x06CA0000` = `WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
| WS_CLIPSIBLINGS | WS_CLIPCHILDREN`) → a titled, movable, non‑resizable window. dgVoodoo
`CenterAppWindow=true` then centers it. Borderless/fullscreen modes restore `00 00 00 85`.

## Focus loss (minimize‑on‑deactivate)

The window procedure (`libIGDisplay.dll` `0x10006550`) routes `WM_ACTIVATE` (6) to worker
`0x10005c90` and `WM_ACTIVATEAPP` (0x1C) to worker `0x10005cb0`. Both are gated on the same
fullscreen byte `[esi+0x46]`:

```
0x10005c90  mov dl,[eax+0x46]; test dl,dl; je <ret> ; else jmp [vtbl+0x7c]   ; WM_ACTIVATE
0x10005cb0  mov dl,[eax+0x46]; test dl,dl; je <ret> ; else jmp [vtbl+0x80]   ; WM_ACTIVATEAPP
```

When the flag is set (always, since fullscreen is forced) losing focus calls the engine's
fullscreen deactivate path (minimize / release the display) → a forced window won't stay open.

**Patch #2 (stay open):** flip the two `je` guards from `74` → `EB` (unconditional `jmp`)
at file offsets **`0x5c9e`** and **`0x5cbe`**, so both handlers always return and do nothing.
Applied for windowed/borderless; restored to `74` for exclusive fullscreen.

## In‑game resolution menu (not a static list)

- Strings at `XMen2.exe 0x6e9800` ("640x480".."1600x1200") are **placeholder `.data`**
  rewritten on every menu open by **`enumModes 0x619ac0`** from the device's enumerated
  D3D8 modes (count global `0xa68da8`). Filter `0x619a40` accepts **any** mode ≥ 640×480
  — no maximum, no 4:3 restriction. So editing the EXE strings does nothing; to add menu
  entries, feed the D3D8 enumeration via dgVoodoo `[DirectXExt] ExtraEnumeratedResolutions`.

## Widescreen correctness (no FOV patch needed)

- 3D camera aspect computed live: **`0x5fad82`** `fild width / fidiv height → camera+0x10`.
- 2D‑UI scale: **`0x5fad70`** `(4/3 ÷ aspect) → 0x6e8488` (the `4/3` constant is at
  `0x6a39f4`). True 16:9 renders undistorted (Hor+); ultrawide > 16:9 is untested.
