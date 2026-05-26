# xwindow / xmonad — Context for AI Agent

xmonad is the window manager. `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` is symlinked to `~/.xmonad/`. xfce4-panel runs along it (built via `home-manager.configsymlink/xmonad.nix`).

## Build

`~/.xmonad/build` uses `$XMONAD_GHC` (set by the nix xmonad wrapper, GHC with xmonad packages); falls back to PATH `ghc`. `set -euo pipefail` + `${1:?}` guard prevents creating misnamed binaries if the output path is missing.

## HLS

`hie.yaml` + `.hie-bios` cradle points HLS to `$XMONAD_GHC` package db; HLS and GHC are installed from the same `haskellPackages` set in `home-manager.configsymlink/nvim.nix` to keep versions in sync.

## ManageHook

Split into: `floatRules`, `browserRules`, `mailRules`, `editorRules`, `calendarRules`, `meetingRules`, `messengerRules`.

## Hooks

- `rescueOffscreenHook` — catches floating windows that move themselves offscreen (e.g. Zoom bug) via `ConfigureEvent` and snaps them back.
- `stripZoomFullscreenHook` — forces Zoom "Meeting" windows to stay tiled. Zoom renames the window to "Meeting" *after* ManageHook runs, so the event hook watches `PropertyNotify` on `_NET_WM_STATE`, `_NET_WM_NAME`, and `WM_NAME`; strips `_NET_WM_STATE_FULLSCREEN` and re-sinks via `W.sink`. Paired with `setEwmhFullscreenHooks`: fullscreen hook returns `idHook` for zoom+Meeting (default `doFullFloat` otherwise).
- `monitorHotplugCfg` / `hideNSPWorkspace` — swaps NSP off visible screens after monitor hotplug.
- `greedyViewNoSwap` — workspace switch variant that swaps visible screens but not hidden.

## xmonad key bindings

- Super tap → Albert toggle
- Alt_L tap → ghostty scratchpad 1 (adaptive half-screen)
- Alt_R tap → ghostty scratchpad 2 (adaptive half-screen)
- Volume keys → `volume-osd`
- Brightness keys → `brightness-osd` (5% steps ≤20%, 10% above)
- Super+VolumeUp → `cycle-audio-output`
- Super+VolumeDown → `cycle-audio-input`
- Super+N → `W.view` (focus workspace without swapping monitors)
- Ctrl+Super+N → `W.greedyView` (bring workspace to current monitor)
- Super+Shift+Enter → gnome-terminal
- Super+\` / Super+= → next screen
- Super+0 → next empty workspace
- Super+S → `scrot -s` selection screenshot to clipboard (image/png via xclip)
- Super+C / Super+V → universal copy/paste, dispatched by keyd as `macro(copy f24)` / `macro(paste f20)` (xmonad doesn't see them — see `keyd/AGENTS.md`)
- Super+Shift+V → `copyq toggle` (clipboard history; moved off Super+V which is now paste)

## Audio OSD system

Three independent dzen2 popups using FIFOs (no flicker on rapid presses):

- `bin/volume-osd` — green, y=100
- `bin/cycle-audio-output` (`/tmp/audio-out-osd-fifo`) — cyan, y=210
- `bin/cycle-audio-input` (`/tmp/audio-in-osd-fifo`) — pink, y=320

Dimensions scale with `Xft.dpi` (base: x=100, w=1240, h=100 at 96dpi). Font: JetBrainsMono Nerd Font, size 36 bold (font respects DPI natively, doesn't need scaling). Auto-hide after 2–3 seconds.

## Brightness OSD

`bin/brightness-osd` — yellow, y=430. Same dzen2 FIFO pattern as audio OSD. Uses `brightnessctl` (nix), 5% steps ≤20%, 10% above.

## Battery OSD

- `bin/battery-osd.py` — thin invocation script (argparse → call into the `osd` library). Built as the `battery-osd` binary via `pkgs.writers.writePython3Bin` in `home.nix`, with the local `osd` Python package as a library dep.
- `osd/` — local Python package (`pyproject.toml` + `src/osd/__init__.py`) providing the cairo + XShape OSD primitives. Built via `pkgs.python3Packages.buildPythonPackage` in `home.nix`. Public API: `OSDStyle` (dataclass: colours, font, layout, anchor, multi-monitor sizing), `render_surface(text, w, h, style, monitor_mm=None)` → `cairo.ImageSurface`, `display_on_all_monitors(text, duration, style)` → one-shot show, `get_monitors(d, root)` → active monitor rects (now 6-tuple `(x, y, w_px, h_px, w_mm, h_mm)`; mm is 0 when EDID didn't report it). Renders text with cairo (configurable fill / outline / drop shadow), then displays in override-redirect X windows whose XShape mask is derived from the rendered alpha channel — the "background" is genuinely transparent (XShape clips). Works without a compositor. Multi-monitor: shows one window per active CRTC. Splits cairo→X `PutImage` calls into row chunks because python-xlib doesn't use `BIG-REQUESTS` for those ops (16-bit length cap → ~256 KB per request). Catches `SIGTERM`/`SIGINT` for clean window teardown.
  - **Sizing**: `width_frac`/`height_frac` (fraction of monitor, default) OR `width_mm`/`height_mm` (absolute mm — same physical size across monitors with different pixel densities; falls back to 96 DPI when EDID mm isn't available). hangul-osd uses mm; battery-osd uses frac.
  - **Anchoring**: `anchor_y` (`top|center|bottom`) + `offset_y_frac`, mirrored by `anchor_x` (`left|center|right`) + `offset_x_frac`.
  - **Alpha caveat**: `fill_alpha` < 1.0 is a brightness multiplier under X11 without a compositor (cairo premultiplies; X11 strips alpha). Real translucency needs picom or similar.
  - **XShape threshold**: pixels with alpha ≥ `style.alpha_threshold` (default 128) become opaque; everything below is clipped. Drop shadows at α=0.7 therefore appear as solid colored regions, not transparent fades — set `shadow_rgba=None` for a glyph-only look.

## Hangul (Korean input) OSD

`bin/hangul-osd.py` — persistent overlay shown on every monitor while ibus's current engine is hangul. Built as `hangul-osd` via `pkgs.writers.writePython3Bin` in `home.nix` (wrapped in a `writeShellScriptBin` that exports `GI_TYPELIB_PATH=${pkgs.ibus}/lib/girepository-1.0` so PyGObject finds the IBus typelib at runtime). Long-lived systemd user service declared in `gnome.nix` (`systemd.user.services.hangul-osd`, `PartOf=graphical-session.target`).

- **Wakeup**: PyGObject + `gi.repository.IBus.Bus().connect("global-engine-changed", …)` — no polling, fires on engine switch.
- **Display**: on transition into hangul, `os.fork()` a child that calls `display_on_all_monitors("한", duration=10**9, style)`; on transition out, `SIGTERM` the child (the osd library tears windows down on SIGTERM). Initial state read via `bus.get_global_engine()` for the boot-already-in-hangul case. SIGCHLD handler reaps if the child dies on its own (e.g. X server restart).
- **Style**: LEGO Bright Light Orange `#F8BB3D` fill, JejuHallasan font, 60×70mm, top-right (anchor_x=right + offset_x_frac=-0.015, anchor_y=top + offset_y_frac=0.02), no outline / no shadow. mm-based sizing means it stays the same physical size on a 4K external + 1080p laptop. **GNOME 100%/200% display-scale is irrelevant** — that scaling only affects GTK apps; xmonad-spawned X windows render in native pixels regardless.
- **Font source**: JejuHallasan ttf is fetched directly via `pkgs.fetchurl` from `google/fonts` (SIL OFL 1.1) into a tiny derivation, not the 2.3 GB `pkgs.google-fonts` mega-package. See `home-manager.configsymlink/AGENTS.md`.
- **Test modes**: `hangul-osd --once` shows the OSD on every monitor without watching ibus (Ctrl-C / SIGTERM to exit — this is what `timeout N hangul-osd --once` uses for visual checks). `hangul-osd --render-png PATH` renders an offline PNG preview.

## Scratchpad system

- Two independent ghostty instances (scratchpad1, scratchpad2), each running `zellij-cycle` with a numeric index (1/2) — attaches to the Nth existing zellij session, falls back to creating `main-N`.
- `scratchpadToggle`: focused → hide, visible elsewhere → focus, hidden → bring to current workspace + float + focus.
- `adaptiveFloat` manage hook: landscape → side-by-side halves, portrait → stacked halves, 2% margins.
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show.

## Zoom notification

- `zoom_linux_float_message_reminder` — floats on all workspaces without stealing focus.
- `annotate_toolbar` — shifted to `8:meeting` by the general zoom rule + floated via a dedicated `doFloat` rule in `meetingRules`. No `title /=?` exclusion is needed because `composeAll` stacks rules (shift + float) additively — the `zoom_linux_float_*` exclusions exist only to stop those windows from being shifted at all, which isn't what we want for the annotate bar.
- **Known bug**: with multi-monitor, moving the mouse toward the notification can trigger workspace swap (focus-follows-mouse + `copyToAll` interaction).

## Other scripts in `xwindow/bin/`

- `weather-genmon` — wttr.in JSON API, python3 parser; 🌙 after sunset / before sunrise; tooltip: current + hourly + 3-day forecast. Used by xfce4-genmon-plugin.
- `sysmon-genmon` — sparkline graphs (CPU, MEM, IO, NET, BAT) via xfce4-genmon-plugin; `color_bar` supports inverted mode for metrics where high=good (battery); history in `/tmp/sysmon-history`, 8 samples.
- `battery-genmon` — standalone battery genmon (fallback; battery is also in `sysmon-genmon`).
- `random-lockscreen` — daily systemd timer; sets gnome lock screen wallpaper from `WALLPAPER_DIR` (default `~/Pictures/Favourites`). Uses `script/logger/log.sh`. Actionable ERRORs for missing dir, empty dir, DBus/schema unreachable, gsettings missing. **HEIC handling**: candidates include `*.heic`; if a HEIC is picked, transcodes it to JPG (full resolution, q≈92) into `${XDG_CACHE_HOME:-~/.cache}/random-lockscreen/<basename>.<src-mtime>.jpg` and sets `picture-uri` to the cached file. Cache key includes source mtime so re-saves trigger re-conversion; older mtime variants for the same basename are removed before writing. ffmpeg over ImageMagick because Ubuntu's `convert-im6.q16` ships a buggy HEIC reader (`error/heic.c/IsHEIFSuccess/139`); ffmpeg's libavcodec unwraps the embedded HEVC/MJPEG stream cleanly. Conversion failure logs WARN and re-rolls to a non-HEIC candidate. Why not skip HEIC entirely: gnome-shell on this machine inherits `GDK_PIXBUF_MODULE_FILE` from a Nix-store `loaders.cache` (set by librsvg's home-manager wrapper) that has no HEIF loader, so a raw HEIC URI silently renders as the primary fallback colour (black) on the lock screen — converting to JPG sidesteps gdk-pixbuf's loader set entirely. Test harness: `script/test_random-lockscreen.sh` (23 assertions + 1 skip when real gsettings is on PATH; fake wallpaper dir + stubbed gsettings).

## Clipboard history

`copyq` (nix) — systemd user service. xmonad Super+Shift+V runs `copyq toggle`. See `keyd/AGENTS.md` for why Super+V is now paste rather than copyq toggle.

## Monitors

- Current setup: 3 monitors — eDP-1 (1920×1200 laptop), DP-1 (3440×1440 ultrawide), DP-3 (1440×2560 portrait); varies by location.
- Multi-monitor: configurations change frequently; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug.
- xfce4-panel bottom bar: 48px, using `avoidStruts`.

## Known issues

- **gnome-flashback "Notifications" tray icon** doesn't respond to clicks (no GNOME Shell notification panel).
