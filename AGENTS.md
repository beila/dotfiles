# Dotfiles Workstation Setup — Context for AI Agent

## TODO List

11. **Remap AltGr → Right Alt** — on laptop keyboard only
1. **Battery indicator** — xfce4-panel plugin or tray applet
2. **Git commit message generator** — AI-assisted or template-based
3. **jj periodic tasks** — auto-fetch, background operations
8. **Copy/paste with Super key** — needs solution that doesn't conflict with keyd/Albert
10. **Fix open-in-container** — firefox-container URL handler
12. try switching to input-remapper from nix

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — modules: gnome.nix, home.nix, neovide.nix, nvim.nix, xdg.nix, xmonad.nix
  - `home.nix` — packages, unfree predicate (albert)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop, lock screen timer)
  - `neovide.nix` — nixGL-wrapped neovide, font copying activation (JetBrains Mono + Nerd Font)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), cargo, biome, python3, taplo, uv
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `system-deps.sh` — apt packages (ibus-hangul, input-remapper, gnome-session-flashback) + session file installs + keyd service setup
- xmonad config: `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` (symlinked to ~/.xmonad/)
- Xmodmap: `~/.dotfiles/xwindow/Xmodmap.symlink` (symlinked to ~/.Xmodmap) — DEPRECATED, replaced by keyd
- keyd config: `~/.dotfiles/keyd/default.conf` (copied to /etc/keyd/ by system-deps.sh)
- input-remapper: `~/.dotfiles/input-remapper-2.configsymlink/` (symlinked to ~/.config/input-remapper-2/)
- jj config: `~/.dotfiles/jj.configsymlink/` (symlinked to ~/.config/jj/), local email in conf.d/local.toml (gitignored)
- fzf functions: `~/.dotfiles/fzf/functions.sh/functions.sh` — jj-first/git-fallback Ctrl-G bindings
- ghostty config: `~/.dotfiles/ghostty.configsymlink/` (symlinked to ~/.config/ghostty/)
- albert config: `~/.dotfiles/albert.configsymlink/` (symlinked to ~/.config/albert/)
- xfce4-panel config: `~/.dotfiles/xfce4.configsymlink/` (symlinked to ~/.config/xfce4/)
- zellij config: `~/.dotfiles/zellij.configsymlink/` (symlinked to ~/.config/zellij/)
- Audio scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Keyboard hotplug: keyd handles remapping at evdev level (no hotplug workaround needed)
- zsh functions: `~/.dotfiles/zsh/functions/c` (copy), `p` (paste), `o` (open) — Wayland/X11 aware

### Key Remapping Stack
- **keyd** (`~/.dotfiles/keyd/default.conf`, system daemon): CapsLock→Ctrl (tap→Esc), Super tap→prog1 (XF86Launch1, albert), Alt_L tap→prog2 (XF86Launch2, ghostty1), Alt_R tap→prog3 (XF86Launch3, ghostty2), Ctrl_R tap→apostrophe, Pause/ScrollLock/PrtSc→volume keys. Applies to all keyboards.
- **input-remapper** (per-device, systemd daemon):
  - Logitech USB Optical Mouse: left-handed (swap left/right)
  - ExpertBT5.0 Mouse (Kensington): left-handed remap + BTN_SIDE→Super+Shift+C (close window) + BTN_LEFT→Super+Tab
  - Kinesis Advantage2 Keyboard (Mac mode — keycodes swapped vs PC):
    - Left Ctrl(29)→Super, Right Super(97)→Super
    - Left Alt(56)→Esc, Right Ctrl(126)→Esc
    - End(107)→Left Alt, PgDn(109)→Right Alt
    - apostrophe(40)→Right Ctrl (tap→apostrophe via keyd)
    - backslash(43)→Tab, PgUp(104)→backslash
- See `~/.dotfiles/xwindow/README.md` for full key remapping diagrams and documentation

### xmonad Key Bindings
- Super tap → Albert toggle
- Alt_L tap → ghostty scratchpad 1 (adaptive half-screen)
- Alt_R tap → ghostty scratchpad 2 (adaptive half-screen)
- Volume keys → volume-osd script (dzen2 FIFO-based, no flicker)
- Super+VolumeUp → cycle audio output (first press shows current, subsequent presses cycle)
- Super+VolumeDown → cycle audio input (same behavior, filters cameras)
- Super+N → W.view (focus workspace without swapping monitors)
- Ctrl+Super+N → W.greedyView (bring workspace to current monitor)
- Super+Shift+Enter → gnome-terminal
- Super+` → next screen
- Super+= → next screen
- Super+0 → next empty workspace

### Audio OSD System
- Three independent dzen2 popups using FIFOs (no flicker on rapid presses):
  - volume-osd: /tmp/volume-osd-fifo, green, y=100
  - audio-out-osd: /tmp/audio-out-osd-fifo, cyan, y=210
  - audio-in-osd: /tmp/audio-in-osd-fifo, pink, y=320
- Dimensions scale with Xft.dpi (base: x=100, w=1240, h=100 at 96dpi)
- Font: JetBrainsMono Nerd Font, size 36 bold (not scaled — font respects DPI natively)
- Auto-hide after 2-3 seconds using lockfile PID check

### Scratchpad System
- Two independent ghostty instances (scratchpad1, scratchpad2)
- Custom `scratchpadToggle`: focused→hide, visible unfocused→focus+reposition, hidden→show+reposition
- `adaptiveFloat` manage hook: landscape→side-by-side halves, portrait→stacked halves, 2% margins
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show/focus
- Identified by x11-instance-name (scratchpad1/scratchpad2)

### Zoom Notification
- `zoom_linux_float_message_reminder` window: floats on all workspaces without stealing focus (via `copyToAll` + `insertPosition Below Older`)

### Known Issues / Constraints
- Nix-installed GTK apps don't show in xfce4-panel systray (library mismatch)
- xfconf needs dbus service registration (handled by Home Manager activation, re-runs on nix updates)
- Fonts need copying to ~/.local/share/fonts for neovide/dzen2 (nix font paths not read by skia/dzen2)
- User is on LDAP (can't chsh), $SHELL is bash, zsh started via exec from .bashrc
- AltGr on laptop keyboard doesn't map to Right Alt (needs per-device remap or xmodmap)
- gnome-flashback "Notifications" tray icon doesn't respond to clicks (no GNOME Shell notification panel)

### Monitors
- Primary: varies (currently 1920x1200, 3440x1440, 1440x2560 portrait)
- Multi-monitor: stacked/side-by-side configurations change frequently
- xfce4-panel bottom bar: 48px gap via xmonad layout gaps (gnome-panel struts broken)
  - Actually using avoidStruts now, gap was removed, panel struts issue was worked around
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
