# keyd / Key Remapping Stack — Context for AI Agent

`keyd` is the system-daemon key remapper (running as root, before X11/Wayland). `input-remapper` handles per-device mouse remaps (running as systemd user). See `keyd/README.md` for the full key remapping documentation.

## keyd (`~/.dotfiles/keyd/`, four files)

Copied to `/etc/keyd/` by `home-manager.configsymlink/system-deps.sh`. Reload with `sudo $(which keyd) reload`, **NOT** `systemctl reload keyd` — the service unit doesn't support reload.

- `common` — shared bindings:
  - CapsLock → Ctrl (tap → Esc)
  - Super tap → prog1 (Albert)
  - Alt_L tap → prog2 (ghostty scratchpad 1)
  - Alt_R tap → prog3 (ghostty scratchpad 2)
  - Ctrl_R tap → apostrophe
  - Pause / ScrollLock / PrtSc → volume keys
  - keyd v2.6.0 maps prog1/2/3 to f21/f22/f23 (evdev 191/192/193)
  - `[meta]` block: Super+C / Super+V → universal copy/paste (see below)
- `default.conf` — all keyboards except device-specific, includes `common`.
- `kinesis.conf` — Kinesis Advantage2 (`29ea:0102`), Mac-mode key swaps, includes `common`.
- `thinkpad.conf` — ThinkPad (`0001:0001:09b4e68d`); includes `common`. Copilot key handling is **shelved** (see "Copilot key" below) — the file only suppresses the stray F23.

## Universal copy/paste

Super+C / Super+V are remapped in `keyd/common`'s `[meta]` block to a two-token macro:

```
c = macro(copy f24)
v = macro(paste f20)
```

- The bare `copy`/`paste` keysym (XF86Copy / XF86Paste, evdev `KEY_COPY` / `KEY_PASTE`) handles ghostty / firefox / GTK / Qt.
- The `f24` / `f20` second token is for **neovide**, whose winit `get_special_key` table drops bare `XF86Copy`/`XF86Paste` but explicitly handles `NamedKey::F1`–`F35`.
- **F21–F23 are reserved for prog1/2/3** (Albert / scratchpads via keyd v2.6.0); F24 is the kernel `KEY_F24` ceiling; F20 is the next free slot below the prog range.
- **Required xkb override** (`home-manager.configsymlink/system-deps.sh` patches `/usr/share/X11/xkb/symbols/inet`): X11 keycodes 198/202 default to `XF86AudioMicMute` / empty under `inet(evdev)`, which winit can't translate to `NamedKey::F20`/`F24`; the patch maps them to `F20`/`F24` so neovide receives the keystrokes. xmonad's startupHook also runs `xmodmap` for fresh checkouts before `script/install`.
- **GNOME caveat**: `home-manager.configsymlink/gnome.nix` strips `<Super>v` from `toggle-message-tray` (moves it to `<Super>m`) so gnome-shell doesn't grab Super+V before keyd's macro runs.
- **Super+Shift+V** opens the copyq history picker via a `[meta+shift]` composite layer that prevents the explicit `v` binding from swallowing the shifted variant.
- **nvim mappings** (`nvim.configsymlink/vimrcs/my-clipboard.lua`, identical for both `<F24>`/`<F20>` and `<XF86Copy>`/`<XF86Paste>`): copy yanks visual selection / `<cword>` / cmdline (mode-aware) to `+`; paste uses `"+P` / `"_d"+P` / `<C-r>+` / `<C-\><C-n>"+pi`. Default `yy`/`p` registers stay independent — only Super+C/V crosses to `+`.
- **Terminal nvim inside ghostty** still needs explicit `"+y`/`"+p` for normal/visual mode (ghostty intercepts XF86Paste before zellij/nvim see it; insert-mode pastes via bracketed paste).
- **F20 in terminals**: ghostty has `keybind = f20=ignore` because the F20 token corrupts zellij's input stream. Don't drop it — neovide depends on F20 and bypasses ghostty.

## Copilot key — SHELVED, not fixable in keyd (do not retry without new info)

The ThinkPad Copilot key (between AltGr and RCtrl) is **not a single keycode** — Lenovo/Microsoft firmware makes it a hardware-macro **chord**. Goal was: tap → Albert, hold+key → Super+key. **Verdict: not achievable in keyd config without sacrificing Super-key-tap=Albert, which is used more. Shelved.** Full investigation below so a future attempt starts informed.

### True raw firmware sequence
Captured with **keyd stopped** (so nothing reorders the AT keyboard — `keyd monitor` shows raw `/dev/input`):
```
Tap:       leftmeta↓ leftshift↓ f23↓ f23↑ leftshift↑ leftmeta↑
Hold+key:  leftmeta↓ leftshift↓ f23↓  <key>  f23↑ leftshift↑ leftmeta↑
```
All three (`leftmeta`, `leftshift`, `f23`) press within microseconds, `leftmeta` first, and bracket the pressed key. The **real Super key sends `leftmeta` alone** (no f23). Note: any `keyd monitor` capture taken *while keyd runs* is **reordered** by `common`'s `leftmeta = overloadt2(...)` buffering — only a keyd-stopped capture shows truth.

### The core conflict (why "both" is impossible)
- **Super-tap = Albert** requires `common`'s `leftmeta = overloadt2(meta, prog1, 150)`.
- **Collapsing the Copilot chord** requires a chord whose first key is `leftmeta` (e.g. `leftmeta+leftshift+f23 = …`).
- An `overloadt2` on `leftmeta` **consumes the `leftmeta` event before the chord engine can buffer it**, so the chord never assembles. Proven by single-variable test: chord fires with a plain `leftmeta` (no `common`), does **not** fire with `common` loaded. Same input keycode → mutually exclusive. Different *output* keycodes don't help; the collision is on the `leftmeta` **input**.
- Maintainer rvaiya (keyd issue [#825](https://github.com/rvaiya/keyd/issues/825)) confirms a deeper wall: *"there is no way to distinguish between leftshift emitted by the left shift key and the one emitted by the copilot key… I agree that this is mostly hopeless."* → **Copilot+Shift+key can never work** (firmware already holds shift; a real shift press registers as a kernel repeat, value 2, not a fresh down).

### What was tried (all failed)
| Attempt | Result | Why |
|---|---|---|
| `f23 = overloadt2(copilot, prog1, 150)` + `[copilot] leftshift = noop` | shift leaked → Copilot+C = Super+Shift+C | overloadt2 defers layer activation; the interrupting `shift` is processed in `[main]` before `[copilot]` is live |
| `f23 = overload(copilot, prog1)` + `[copilot] leftshift = noop` | **stuck Shift → dead mouse** | `noop` ate the `shift↑` whose `shift↓` fired in another layer → stranded modifier until next Super tap |
| `leftmeta+leftshift+f23 = overload(meta, prog1)` **with** `include common` | chord didn't fire; tap leaked raw `<F23>` (`<2a>`); Copilot+C still M-S-c | `common`'s `leftmeta = overloadt2` consumes leftmeta first |
| `leftmeta+leftshift+f23 = layer(control)` / `overload(meta, prog1)` **without** `common` | **WORKS**: Copilot+C copies, +4 switches, tap=Albert, clean Super, no stuck key | nothing overloads `leftmeta`, so the chord assembles |

So a config that fully works exists — but only **without** `common`'s `leftmeta` overload, i.e. you'd lose Super-key-tap=Albert. That tradeoff was rejected (Super used more than Copilot).

### If revisiting
- The known-good full-Copilot config (accept losing Super-tap=Albert): `include common`, then in `[main]` of `thinkpad.conf` override `leftmeta = layer(meta)` and add `leftmeta+leftshift+f23 = overload(meta, prog1)`. Verified working on this hardware.
- Hardware note: this unit does **not** block keys while Copilot is held (some BT keyboards do — keyd issue #1241). Confirmed via raw capture (the `<key>` registers mid-hold).
- Kernel angle: commit `907bc9268a5a` (in 6.13+) addresses some Copilot variants. We're on **6.17 and the meta+shift+f23 chord still appears**, so the kernel fix does not cover this unit. If a future kernel collapses it to a single keycode, the whole problem dissolves — re-test with a keyd-stopped raw capture.
- External tool [`mishoo/exorcise-copilot`](https://github.com/mishoo/exorcise-copilot): a ~200-line C++ evdev-grab+uinput remapper. **Rejected**: it `libevdev_grab`s the same physical keyboard keyd already grabs (conflict — would force pulling the ThinkPad keyboard out of keyd entirely and reimplementing all current remaps), hardcodes output to Right Ctrl (not Super), and its own README admits the modifier combos are imperfect.
- Current `thinkpad.conf` keeps only `f23 = noop` (suppress the stray F23 so a tap doesn't emit `<2a>` into the focused app). Hold passes `leftmeta`+`leftshift` through as **Super+Shift** via `common` (functional for non-shift-sensitive Super bindings — this is the accepted baseline; user prioritises Super-key-tap=Albert over a cleaner Copilot hold).
- The old `leftshift+leftmeta = layer(meta)` and `[meta] f23 = timeout(...)` lines were removed as dead code. They *look* like they'd collapse the Copilot chord to plain Super on hold, and **probably did work historically — before `common` gained `leftmeta = overloadt2(meta, prog1, 150)`** (added to give the physical Super key tap=Albert). Once that overload existed it consumed `leftmeta` before the 2-key chord could assemble, so the line silently stopped firing. Confirmed: the first raw capture (original config, pre-cleanup) showed hold producing `Super+Shift+<key>`, not plain Super — i.e. removing the line changed nothing. So "Copilot hold used to give plain Super" and "it gives Super+Shift now" are both true, separated by the addition of the `leftmeta` overload, not by this cleanup.

## input-remapper (`~/.dotfiles/input-remapper-2.configsymlink/`, mice only)

Symlinked to `~/.config/input-remapper-2/`. Per-device, runs as systemd user daemon.

- Logitech USB Optical Mouse: left-handed.
- ExpertBT5.0 Mouse (Kensington): left-handed + `BTN_SIDE` → Super+Shift+C (close window) + `BTN_LEFT` → Super+Tab.

## Known issues

- **AltGr on laptop keyboard** doesn't map to Right Alt — needs a keyd per-device config.
- **input-remapper stale device list** (after Bluetooth reconnect, or the daemon simply running for days): the daemon's internal device list goes stale and autoload doesn't re-apply to the live evdev node — `xinput list` shows BOTH the original device AND `input-remapper <name> forwarded`, but real button presses pass through unmapped (e.g. the Logitech left-handed swap silently reverts to right-handed). Fix: run `reloadmouse` (in `xwindow/bin/`). If it still says "Device unknown", restart the daemon: `sudo systemctl restart input-remapper-daemon`.
  - **Why `reloadmouse`, not the bare `input-remapper-control --command autoload`**: the interactive session (ghostty, anything Nix-wrapped) exports Nix's `GI_TYPELIB_PATH` (glib 2.88.1) globally. The system `/usr/bin/input-remapper-control` is a system-Python program; it imports `gi.repository.Gio` via `pydbus`, picks up the Nix typelib, and dies with `undefined symbol: g_string_copy`. `reloadmouse` re-execs the same CLI under `env -i` (clean PATH/HOME/XDG_RUNTIME_DIR) so it never sees the Nix glib. The login autostart (`/etc/xdg/autostart/input-remapper-autoload.desktop`) and the hotplug udev rule (`/usr/lib/udev/rules.d/60-input-remapper-daemon.rules`) run in clean envs, so they're unaffected — only manual recovery from a Nix-polluted shell was broken.
- **There is exactly one live left-handed swap: the input-remapper preset above.** An older hwdb rule (`system/90-left-mouse.hwdb`) for the same Logitech mouse was deleted — it was never compiled into `/etc/udev/hwdb.bin` nor installed in `/etc/udev/hwdb.d/`, so it did nothing. Don't reintroduce an hwdb (or the commented `pointer =` lines in `xwindow/Xmodmap.symlink`) to fix a right-handed mouse — a second swap would cancel out input-remapper's. The mouse going right-handed means the preset stopped applying; run `reloadmouse`.
