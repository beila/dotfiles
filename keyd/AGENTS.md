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
- `thinkpad.conf` — ThinkPad (`0001:0001:09b4e68d`), Copilot key → tap: Albert, hold: Super; includes `common`.

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

## input-remapper (`~/.dotfiles/input-remapper-2.configsymlink/`, mice only)

Symlinked to `~/.config/input-remapper-2/`. Per-device, runs as systemd user daemon.

- Logitech USB Optical Mouse: left-handed.
- ExpertBT5.0 Mouse (Kensington): left-handed + `BTN_SIDE` → Super+Shift+C (close window) + `BTN_LEFT` → Super+Tab.

## Known issues

- **keyd v2.5.0** parser fails on UTF-8 box-drawing characters in `default.conf` comments (works in `kinesis.conf`).
- **AltGr on laptop keyboard** doesn't map to Right Alt — needs a keyd per-device config.
- **input-remapper after Bluetooth reconnect**: when a BT mouse/trackball drops + re-attaches mid-session, the daemon's internal device list goes stale and autoload doesn't re-apply to the new evdev node — `xinput list` shows BOTH the original device AND `input-remapper <name> forwarded`, but real button presses pass through unmapped. First try `input-remapper-control --command autoload`; if that still says "Device unknown", restart the daemon: `sudo systemctl restart input-remapper-daemon`. If this happens repeatedly, automate via a udev rule that triggers `autoload` on `add` events for the device, or a systemd path/dispatcher hook.
