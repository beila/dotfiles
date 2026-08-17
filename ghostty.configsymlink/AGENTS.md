# ghostty — Context for AI Agent

Symlinked to `~/.config/ghostty/`.

## Config knobs

- `gtk-titlebar = false` + `window-show-tab-bar = never` — no decorations and no tab bar. XMonad's `windowTags` overlay supplies one compact, DPI-aware top-right title tag for every visible Ghostty window, tiled or floating (see `xwindow/AGENTS.md`). The always-on tab bar cost ~46px of full width with a close button, and GTK4 CSS has no `max-width` so `gtk-custom-css` cannot narrow it. Both scratchpads launch `zmx-select`, which writes `zmx` or `[<session>]` into the window title for the tag. Config changes need `ctrl+shift+,` (`reload_config`) or a fresh instance; a running ghostty keeps its loaded config until the process is killed.
- `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes; works around zellij occasionally failing to parse kitty keyboard protocol CSI u sequences under rapid key repeat (see `zellij.configsymlink/AGENTS.md`).
- `keybind = f20=ignore` — swallows the F20 token from keyd's `macro(paste f20)` so its CSI doesn't corrupt zellij's input stream. F20 only exists for neovide, which bypasses ghostty.

## Terminfo

- `pkgs.ghostty.terminfo` installed via `home-manager.configsymlink/home.nix`; `~/.terminfo` symlinked to the nix-store terminfo dir so ncurses finds `xterm-ghostty` at process startup.

## Cross-references

- Universal copy/paste — ghostty intercepts `XF86Paste` before zellij/nvim see it, so terminal nvim inside ghostty needs explicit `"+y` / `"+p` for normal/visual mode (insert-mode pastes via bracketed paste). See `keyd/AGENTS.md`.
