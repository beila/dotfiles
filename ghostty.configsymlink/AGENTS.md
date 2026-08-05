# ghostty — Context for AI Agent

Symlinked to `~/.config/ghostty/`.

## Config knobs

- `gtk-titlebar = false` + `window-show-tab-bar = always` — no window decorations, but the tab bar stays up even with a single tab so the OSC title is visible per window. `zsh/terminal.zsh` prefixes that title with `[$ZMX_SESSION]`, which is how a zmx-attached window identifies itself; unlike the prompt it survives a long-running command, and unlike a panel indicator it's per window. Costs ~46px at the top (GTK's tab-row height, not configurable; `gtk-tabs-location` can move it to another edge). Full `gtk-titlebar = true` would show the same title but ~48px with minimize/maximize/close/hamburger buttons that are useless under xmonad. Changes need `ctrl+shift+,` (`reload_config`) or a fresh instance — a running ghostty keeps its loaded config.
- `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes; works around zellij occasionally failing to parse kitty keyboard protocol CSI u sequences under rapid key repeat (see `zellij.configsymlink/AGENTS.md`).
- `keybind = f20=ignore` — swallows the F20 token from keyd's `macro(paste f20)` so its CSI doesn't corrupt zellij's input stream. F20 only exists for neovide, which bypasses ghostty.

## Terminfo

- `pkgs.ghostty.terminfo` installed via `home-manager.configsymlink/home.nix`; `~/.terminfo` symlinked to the nix-store terminfo dir so ncurses finds `xterm-ghostty` at process startup.

## Cross-references

- Universal copy/paste — ghostty intercepts `XF86Paste` before zellij/nvim see it, so terminal nvim inside ghostty needs explicit `"+y` / `"+p` for normal/visual mode (insert-mode pastes via bracketed paste). See `keyd/AGENTS.md`.
