# ghostty — Context for AI Agent

Symlinked to `~/.config/ghostty/`.

## Config knobs

- `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes; works around zellij occasionally failing to parse kitty keyboard protocol CSI u sequences under rapid key repeat (see `zellij.configsymlink/AGENTS.md`).

## Terminfo

- `pkgs.ghostty.terminfo` installed via `home-manager.configsymlink/home.nix`; `~/.terminfo` symlinked to the nix-store terminfo dir so ncurses finds `xterm-ghostty` at process startup.

## Cross-references

- Universal copy/paste — ghostty intercepts `XF86Paste` before zellij/nvim see it, so terminal nvim inside ghostty needs explicit `"+y` / `"+p` for normal/visual mode (insert-mode pastes via bracketed paste). See `keyd/AGENTS.md`.
