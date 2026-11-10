# ghostty — Context for AI Agent

Symlinked to `~/.config/ghostty/`.

## Config knobs

- `clipboard-paste-protection = false` — skips the confirmation dialog for content Ghostty considers unsafe, including multiline text outside bracketed-paste mode.
- `gtk-titlebar = false` + `window-show-tab-bar = never` — no decorations and no tab bar. XMonad's `windowTags` overlay supplies one compact, DPI-aware top-right title tag for every visible Ghostty window, tiled or floating (see `xwindow/AGENTS.md`). The always-on tab bar cost ~46px of full width with a close button, and GTK4 CSS has no `max-width` so `gtk-custom-css` cannot narrow it. Both scratchpads launch `zmx-select`, which writes the mutable OSC title and stores the stable session name in `_ZMX_SESSION` on Ghostty's exported `$WINDOWID`; XMonad composes both values. Config changes need `ctrl+shift+,` (`reload_config`) or a fresh instance; a running ghostty keeps its loaded config until the process is killed.
- `keybind = ctrl+{j,k,n,p,s}=text:\xNN` — sends legacy control codes; works around terminal session relays occasionally leaking kitty keyboard protocol CSI u sequences into foreground TUIs. Control-S is required by `_jh`/`_jhh`'s changed-file toggle: without the override, a leaked `ESC[115;5u` can leave literal `5;5u` in fzf's query after the next key. See `zellij.configsymlink/AGENTS.md` and `home-manager.configsymlink/AGENTS.md`.
- `keybind = f20=ignore` — prevents F20 from entering terminal input when XMonad does not handle it. XMonad now uses the existing F20 token for image paste into a wrapped Codex/Claude session. The preceding XF86Paste still handles text. Neovide receives a targeted F20 event and bypasses Ghostty.

## Terminfo

- `pkgs.ghostty.terminfo` installed via `home-manager.configsymlink/home.nix`; `~/.terminfo` symlinked to the nix-store terminfo dir so ncurses finds `xterm-ghostty` at process startup.

## Cross-references

- Universal copy/paste — ghostty intercepts `XF86Paste` before zellij/nvim see it, so terminal nvim inside ghostty needs explicit `"+y` / `"+p` for normal/visual mode (insert-mode pastes via bracketed paste). See `keyd/AGENTS.md`.
