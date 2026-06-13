# zellij — Context for AI Agent

Symlinked to `~/.config/zellij/`.

## Keybindings (config.kdl)

- **Normal mode**: Alt-Tab → Detach (triggers `zellij-cycle` session switch — see `bin/AGENTS.md`); Alt-W → session manager (built-in plugin); Ctrl-Tab → next tab; Alt-h/j/k/l → MoveFocus; Alt-Shift-h/j/k/l → MovePane.
- **Move mode**: Alt-Shift-h/l → move tab left/right; Ctrl-Shift-h/j/k/l → move pane.

## Known issues

- **zellij + kitty keyboard protocol**: under rapid key repeat, zellij occasionally fails to parse CSI u sequences. Worked around by sending legacy control codes from ghostty for ctrl-j/k/n/p (see `ghostty.configsymlink/AGENTS.md`).
