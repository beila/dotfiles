# zellij — Context for AI Agent

Symlinked to `~/.config/zellij/`.

## Keybindings (config.kdl)

- **Normal mode**: Alt-Tab → Detach (triggers `zellij-cycle` session switch — see `bin/AGENTS.md`); Alt-W → session manager (built-in plugin); Ctrl-Tab → next tab; Alt-h/j/k/l → MoveFocus; Alt-Shift-h/j/k/l → MovePane.
- **Move mode**: Alt-Shift-h/l → move tab left/right; Ctrl-Shift-h/j/k/l → move pane.

## Known issues

- **Terminal relays + kitty keyboard protocol**: zellij can fail to parse CSI u sequences under rapid key repeat, and zmx can restore a keyboard-protocol mode that the newly foregrounded program did not request. Worked around by sending legacy control codes from ghostty for Control-J/K/N/P/S (see `ghostty.configsymlink/AGENTS.md`).
