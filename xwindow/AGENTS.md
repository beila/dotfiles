# xwindow / xmonad — Context for AI Agent

xmonad is the window manager. `xwindow/xmonad.symlink/xmonad.hs` is symlinked to `~/.xmonad/`. xfce4-panel runs alongside it (built via `home-manager.configsymlink/xmonad.nix`).

## Build

`~/.xmonad/build` uses `$XMONAD_GHC` (set by the nix xmonad wrapper, GHC with xmonad packages); falls back to PATH `ghc`. `set -euo pipefail` + `${1:?}` guard prevents creating misnamed binaries if the output path is missing.

## HLS

`hie.yaml` + `.hie-bios` cradle points HLS to `$XMONAD_GHC` package db; HLS and GHC are installed from the same `haskellPackages` set in `home-manager.configsymlink/nvim.nix` to keep versions in sync.

## Borders (focus indicator)

`borderWidth = 1`, `focusedBorderColor = "#F8BB3D"` (LEGO orange, same accent as hangul-osd), `normalBorderColor = "#1d1d1d"`, `smartBorders` in the layoutHook. Paired with a picom glow (see `home-manager.configsymlink/picom.nix`) — the thin solid border gives a crisp edge while picom's focused-only centred shadow (radius 14, `#F8BB3D`, full opacity) adds a soft gradient halo that starts at border colour and fades over ~14px.

- **Unfocused is "invisible colour", not 0px**: xmonad keeps the window footprint constant, so toggling border width between 0 and N resizes the client by 2×N on every focus change — terminals get SIGWINCH and re-wrap, and focus-follows-mouse makes that fire on every mouse sweep. Painting the border near-black instead keeps geometry stable; the cost is a 2×1px dark seam at unfocused–unfocused junctions.
- **`smartBorders`** (not `lessBorders` with a custom strategy) already does the wanted thing: hides the border only when there's a single window _and_ a single screen, so with multiple monitors the focused screen stays identifiable. Its width toggle only fires when the window count changes, which is rare enough that the resize is acceptable.
- **Picom (compositor)**: `home-manager.configsymlink/picom.nix` — xrender backend (no GL, no nixGL wrapper needed), shadow-only config. Only the focused window gets a shadow; unfocused, docks, notifications, and dzen OSDs are excluded. The shadow is centred (offset = −radius) so it reads as a glow, not a drop-shadow. `use-ewmh-active-win = true` ensures picom reads `_NET_ACTIVE_WINDOW` (which xmonad sets correctly) rather than relying on X11 FocusIn/Out events (which can falsely mark windows on inactive monitors as focused). Runs under `graphical-session.target`.
- **`raiseFocused`** (logHook): calls `raiseWindow` on the focused window after every focus change. Picom draws a window's shadow at that window's Z-level, so without this, the glow is hidden wherever a higher-stacked tiled neighbor overlaps the shadow zone. Raising the focused window ensures its glow paints above all neighbors symmetrically.
  - **Must purge EnterNotify after raising** (`clearEvents enterWindowMask`, guarded by `unless isMouseFocused` — same idiom as core's `windows`): restacking synthesizes EnterNotify on whatever window sits under the pointer, and with focus-follows-mouse that event yanks focus straight back. Symptom before the fix: Super+Tab from a window under the pointer to another window would bounce focus back within one frame (e.g. ghostty→neovide un-switchable). Core purges these after its own `restackWindows`, but the logHook runs _after_ that purge, so our raises need their own.

## ManageHook

Split into: `floatRules`, `browserRules`, `mailRules`, `editorRules`, `calendarRules`, `meetingRules`, `messengerRules`.

## Hooks

- `rescueOffscreenHook` — catches floating windows that move themselves offscreen (e.g. Zoom bug) via `ConfigureEvent` and snaps them back.
- `stripZoomFullscreenHook` — forces Zoom "Meeting" windows to stay tiled. Zoom renames the window to "Meeting" _after_ ManageHook runs, so the event hook watches `PropertyNotify` on `_NET_WM_STATE`, `_NET_WM_NAME`, `WM_NAME`; strips `_NET_WM_STATE_FULLSCREEN` and re-sinks via `W.sink`. Paired with `setEwmhFullscreenHooks`: fullscreen hook returns `idHook` for zoom+Meeting (default `doFullFloat` otherwise).
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
- Super+Shift+V → `copyq toggle` (clipboard history)

## OSD library (`xwindow/osd/`)

Local Python package built via `pkgs.python3Packages.buildPythonPackage` in `home.nix`. Provides cairo + XShape primitives:

- `OSDStyle` — dataclass: colours, font, layout, anchor, multi-monitor sizing
- `render_surface(text, w, h, style, monitor_mm=None)` → `cairo.ImageSurface`
- `display_on_all_monitors(text, duration, style)` — one-shot show
- `get_monitors(d, root)` — active monitor rects, 6-tuple `(x, y, w_px, h_px, w_mm, h_mm)`; mm is 0 when EDID didn't report it.

Renders text with cairo (configurable fill / outline / drop shadow), then displays in override-redirect X windows whose XShape mask is derived from the rendered alpha channel — the "background" is genuinely transparent (XShape clips). Works without a compositor. Multi-monitor: one window per active CRTC. Splits cairo→X `PutImage` calls into row chunks because python-xlib doesn't use `BIG-REQUESTS` (16-bit length cap → ~256 KB per request). Catches `SIGTERM`/`SIGINT` for clean window teardown.

- **Sizing**: `width_frac`/`height_frac` (fraction of monitor) OR `width_mm`/`height_mm` (absolute mm — same physical size across monitors with different pixel densities; falls back to 96 DPI when EDID mm isn't available). hangul-osd uses mm; battery-osd uses frac.
- **Anchoring**: `anchor_y` (`top|center|bottom`) + `offset_y_frac`, mirrored for `anchor_x` + `offset_x_frac`.
- **Font backend**: `use_pango=False` (default) uses cairo's toy font API — fast but family matching is fragile in sessions with elaborate fontconfig fallback chains. `use_pango=True` routes through Pango/PangoCairo for reliable fontconfig + harfbuzz matching, ~50–100 ms slower per render. Set `font_file=<path>` together with `use_pango=True` to register a ttf as an application-private font via `FcConfigAppFontAddFile` — this is what makes JejuHallasan visible to Pango despite incomplete `en` glyph coverage.
- **Alpha caveat**: `fill_alpha` < 1.0 is a brightness multiplier under X11 without a compositor (cairo premultiplies; X11 strips alpha). Real translucency needs picom or similar.
- **XShape threshold**: pixels with alpha ≥ `style.alpha_threshold` (default 128) become opaque; everything below is clipped. Drop shadows at α=0.7 therefore appear as solid coloured regions, not transparent fades — set `shadow_rgba=None` for a glyph-only look.
- **Scanline padding (BadLength trap)**: the 1-bit XShape mask is built in `_make_shape_mask` and uploaded via `PutImage`. X11 requires every XYBitmap scanline to be padded to `bitmap_format_scanline_pad` (32 bits on every modern server), and the server derives the request's expected byte length from that padding. Padding rows only to whole _bytes_ (`(iw+7)//8`) makes the buffer shorter than the header claims → `Xlib.error.BadLength` on opcode 72 (PutImage), one per monitor, and **no OSD appears** (PNG/`render_surface` paths are unaffected since they never hit X). Both `_make_shape_mask` and the `_chunked_put_image` `bytes_per_row` arg must round to 4 bytes: `((iw+31)//32)*4`. This stayed hidden until a glyph size produced a mask width that wasn't a multiple of 32 px. The ZPixmap (colour) upload is naturally 4-byte aligned (`iw*4`), so only the mask path is affected.

## Audio / brightness OSDs

Three independent dzen2 popups using FIFOs (no flicker on rapid presses):

- `bin/volume-osd` — green, y=100
- `bin/cycle-audio-output` (`/tmp/audio-out-osd-fifo`) — cyan, y=210
- `bin/cycle-audio-input` (`/tmp/audio-in-osd-fifo`) — pink, y=320
- `bin/brightness-osd` — yellow, y=430. Uses `brightnessctl` (nix), 5% steps ≤20%, 10% above.

Dimensions scale with `Xft.dpi` (base: x=100, w=1240, h=100 at 96dpi). Font: JetBrainsMono Nerd Font, size 36 bold. Auto-hide after 2–3 seconds.

## Battery OSD

`bin/battery-osd.py` is a thin invocation script (argparse → call into the `osd` library), built as the `battery-osd` binary via `pkgs.writers.writePython3Bin` in `home.nix`.

## Hangul (Korean input) OSD

`bin/hangul-osd.py` — persistent overlay shown on every monitor while ibus-hangul is in Hangul mode. Long-lived systemd user service (`systemd.user.services.hangul-osd` in `gnome.nix`, `PartOf=graphical-session.target`). Built as a `writeShellScriptBin` wrapper that exports `GI_TYPELIB_PATH` and `HANGUL_OSD_FONT_FILE` before exec'ing the inner `writePython3Bin` impl — see `home-manager.configsymlink/AGENTS.md`.

### Mode-change source: `org.gnome.Flashback.InputSources`

Subscribes to the D-Bus signal `org.gnome.Flashback.InputSources.Changed` (path `/org/gnome/Flashback/InputSources`) via `Gio.DBusConnection.signal_subscribe`. Push, no polling. Each notification triggers `GetInputSources()` whose returned `current_source` dict contains `icon-text` — `'한'` when the engine is in Hangul mode, `'EN'` otherwise.

**Why this signal source and not ibus directly**:

- IBus daemon doesn't grab the keyboard. Source-level hotkeys (`org.freedesktop.IBus.general.hotkey.triggers`) are processed by GNOME Shell — which is not running under xmonad+gnome-flashback. So a two-source `xkb:us` + `ibus:hangul` pattern with Shift+Space at the source level doesn't switch at all.
- ibus-hangul's engine-internal `switch-keys` (Shift+Space) DOES toggle Hangul/English, because IBus IM clients forward keystrokes to the active engine regardless of WM. But IBus does not broadcast the engine-internal mode change on D-Bus (verified with `dbus-monitor`), and `IBus.Bus.connect("global-engine-changed", ...)` raises `unknown signal name` in this PyGObject binding.
- `gnome-flashback` is running and watches ibus engine state out-of-band; its `InputSources` D-Bus interface emits `Changed` on every engine-internal mode flip and on every source switch. That's the only push signal that fires reliably here.

Implementation requires `gnome-session=gnome-flashback-xmonad`. The alternative — a custom IBus PanelService — would also work and remove the gnome-flashback dependency, but adds a lot of code for no functional gain.

### Why a long-lived daemon, not a per-toggle script

A previous design wired Shift+Space to xmonad's keybinding map and shelled out per-press, but xmonad's grab swallows the keystroke before it reaches ibus-hangul, so Hangul mode itself stops working. The daemon listening to gnome-flashback's signal sidesteps that — the user keeps using `Shift+Space` exactly as before, ibus-hangul handles the actual toggle, we just observe.

### Style

LEGO Bright Light Orange `#F8BB3D`, JejuHallasan, 60×70mm, top-right (`anchor_x=right`, `offset_x_frac=-0.015`, `anchor_y=top`, `offset_y_frac=0.02`), no outline, no shadow.

- **mm sizing** so the OSD looks the same physical size on monitors with different pixel densities (4K external + 1080p laptop). GNOME's display-scale (100% / 200%) is irrelevant: it only affects GTK applications; X windows we paint via Xlib in native pixels are unaffected.
- **No outline / no shadow** because XShape mask thresholds at `alpha_threshold=128` — drop shadows at α=0.7 (= 178) end up _inside_ the mask and render as solid coloured regions, not faded shadows. Pure-glyph look only.

### Font matching: JejuHallasan via Pango + fontconfig app-font

JejuHallasan reaches cairo through three indirections, none of which work in isolation in our session:

1. **cairo's toy font API silently falls back** when the requested family is hard to match against fontconfig's chain (this session's fontconfig prepends Noto Sans + every script-specific Noto Sans + DejaVu LGC Sans before any user family). Hangul codepoints render as `.notdef` rectangles even though `fc-match` resolves the family correctly.
2. **PangoCairo's default fontmap also fails**: it filters out fonts that don't satisfy `en` language coverage. JejuHallasan is missing 20 ASCII glyphs (`fc-validate` confirms), so it's hidden from `PangoCairo.FontMap.list_families()` and `set_family("JejuHallasan")` matches some fallback.
3. **fontconfig's app-font set bypasses the lang-coverage filter**: `FcConfigAppFontAddFile(current_config, ttf_path)` registers the font privately for our process, after which Pango's matcher sees it.

Working stack: **Pango (`use_pango=True` on the OSDStyle) + `font_file` pointing at the ttf**. The osd library's `_render_with_pango` calls `_fc_app_font_add(font_file)` once before creating the layout. ctypes calls `FcConfigAppFontAddFile` directly so we don't pull in a separate Python binding.

### Test modes

- `hangul-osd --once` — shows the OSD on every monitor unconditionally; Ctrl-C / SIGTERM to clear. (`timeout 10 hangul-osd --once` for visual sanity.)
- `hangul-osd --render-png PATH` — offline preview PNG.

## Scratchpad system

- Two independent ghostty instances (scratchpad1, scratchpad2), each running `zellij-cycle` with a numeric index (1/2) — attaches to the Nth existing zellij session, falls back to creating `main-N`.
- `scratchpadToggle`: per-scratchpad (left-alt → ghostty1, right-alt → ghostty2); behavior branches on whether the window is fullscreen. Fullscreen is detected from xmonad's **float map** (`W.floating` entry == `RationalRect 0 0 1 1`, what `doFullFloat` sets), **not** the `_NET_WM_STATE_FULLSCREEN` atom — exiting fullscreen runs `doSink`, which leaves that atom stale on a now-tiled window:
  - **Fullscreen** — stuck in its own workspace, never hidden: focused → `toggleWS' ["NSP"]` jumps back to the previously viewed workspace (pressing again returns, toggling between the two); parked elsewhere → jump to its workspace and focus, preserving fullscreen.
  - **Not fullscreen** (half-screen float) — classic per-window show/hide: focused → hide to NSP; visible on another screen → focus; hidden → bring to current workspace + float + focus.
- `adaptiveFloat` manage hook: landscape → side-by-side halves, portrait → stacked halves, 2% margins.
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show.

## Zoom notification

- `zoom_linux_float_message_reminder` — floats on all workspaces without stealing focus.
- `annotate_toolbar` — shifted to `8:meeting` by the general zoom rule + floated via a dedicated `doFloat` rule in `meetingRules`. No `title /=?` exclusion is needed because `composeAll` stacks rules (shift + float) additively — the `zoom_linux_float_*` exclusions exist only to stop those windows from being shifted at all, which isn't what we want for the annotate bar.
- **Known bug**: with multi-monitor, moving the mouse toward the notification can trigger workspace swap (focus-follows-mouse + `copyToAll` interaction).

## Other scripts in `xwindow/bin/`

- `weather-genmon` — wttr.in JSON API, python3 parser; 🌙 after sunset / before sunrise; tooltip: current + hourly + 3-day forecast. Used by xfce4-genmon-plugin.
- `sysmon-genmon` — braille sparkline graphs (CPU, MEM, IO, NET, TEMP, BAT) via xfce4-genmon-plugin; one cell = 2 samples × 5 dot-heights; history in `/tmp/sysmon-history`, `CELLS=15` → 30 samples (≈10 min at 20s poll). `color_pair` supports inverted mode for metrics where high=good (battery). **Color tracks the rendered dot-height, not the raw percent** — `severity()` takes the quantized height (0..4) so a given bar height is always one color (h1,h2→green, h3→yellow, h4→red; inverted via `eff = 5-h`). Coloring off raw percent would split a height band across two colors because `height()`'s nearest-rounding boundaries (37.5/62.5/87.5%) don't line up with percent thresholds.
  - **TEMP** (`🌡️` sparkline + tooltip): CPU package die temp, normalized **40–100°C → 0–100%** so the height/severity quantizer paints it green ≤~77°C, yellow ~78–92°C, red ≥~92°C. Range chosen because idle is ~66°C and crit is 105°C — keeps idle green but reaches red before throttling. Sensor resolved by **driver name, not fixed `hwmonN`** (hwmon indices reshuffle across boots) via `hwmon_by_name`: `coretemp`/`temp1_input` ("Package id 0"), falling back to the `x86_pkg_temp` thermal zone, then `thinkpad`/`temp1_input`.
  - **FAN** (tooltip-only, no panel sparkline): `thinkpad`/`fan1_input` RPM. Tooltip-only because a sparkline would need an arbitrary RPM→% normalization; the raw current value is the honest, compact signal and keeps the panel narrow.
  - Both temp and fan show `n/a` in the tooltip when the sensor isn't found; temp pushes `-1` ("no data") to history so missing samples render blank, not as a false low reading.
- `battery-genmon` — standalone battery genmon (fallback; battery is also in `sysmon-genmon`).
- `random-lockscreen` — daily systemd timer; sets gnome lock screen wallpaper from `WALLPAPER_DIR` (default `~/Pictures/Favourites`). Uses `script/logger/log.sh`. Actionable ERRORs for missing/empty dir, DBus/schema unreachable, gsettings missing.
  - **HEIC handling**: candidates include `*.heic`; if a HEIC is picked, transcodes it to JPG (full resolution, q≈92) into `${XDG_CACHE_HOME:-~/.cache}/random-lockscreen/<basename>.<src-mtime>.jpg` and sets `picture-uri` to the cached file. Cache key includes source mtime so re-saves trigger re-conversion; older mtime variants for the same basename are removed before writing. ffmpeg over ImageMagick because Ubuntu's `convert-im6.q16` ships a buggy HEIC reader (`error/heic.c/IsHEIFSuccess/139`); ffmpeg's libavcodec unwraps the embedded HEVC/MJPEG cleanly. Conversion failure logs WARN and re-rolls.
  - **Why not skip HEIC entirely**: gnome-shell on this machine inherits `GDK_PIXBUF_MODULE_FILE` from a Nix-store `loaders.cache` (set by librsvg's home-manager wrapper) that has no HEIF loader, so a raw HEIC URI silently renders as the primary fallback colour (black) on the lock screen — converting to JPG sidesteps gdk-pixbuf's loader set entirely.
  - Test harness: `script/test_random-lockscreen.sh`.
- `on-input-change` — called by inputplug on `XISlaveAdded`; sleeps 3s for GNOME's keymap reset to settle, then re-applies `xmodmap ~/.Xmodmap`.
- `reloadmouse` — re-triggers input-remapper autoload when its device list goes stale (mouse silently reverts to right-handed). Re-execs `/usr/bin/input-remapper-control --command autoload` under `env -i` to dodge the session's leaked Nix `GI_TYPELIB_PATH`, which otherwise crashes the system CLI (`undefined symbol: g_string_copy`). See `keyd/AGENTS.md`.

## Clipboard history

`copyq` (nix) — systemd user service. xmonad Super+Shift+V runs `copyq toggle`. Super+V is universal paste (see `keyd/AGENTS.md`).

## Monitors

Multi-monitor configurations vary by location; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug. xfce4-panel bottom bar: 48px, using `avoidStruts`.

## Known issues

- **gnome-flashback "Notifications" tray icon** doesn't respond to clicks (no GNOME Shell notification panel).
