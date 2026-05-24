-- Universal Super+C / Super+V handling inside nvim.
--
-- Setup chain: xmonad binds Super+C/V → ~/.dotfiles/bin/copy-paste-route →
-- xdotool emits Ctrl+Shift+C/V to the focused window class. Both ghostty
-- (terminal-nvim) and neovide are in the script's "terminal" list, so both
-- receive the same Ctrl+Shift+C/V keystroke. These mappings then make nvim
-- act on the system clipboard via the `+` register.
--
-- Why not also `set clipboard=unnamedplus`?
-- The user explicitly wants the unnamed register to stay independent —
-- `yy` and `p` should keep using buffer 0, not the system clipboard. Only
-- the explicit Super+C/V (which arrives as Ctrl+Shift+C/V) crosses over
-- to `+`.
--
-- Behaviour by mode:
--   - normal   : Super+C copies the line under cursor (`"+yy`); Super+V
--                pastes from `+` after cursor (`"+p`).
--   - visual   : Super+C copies the visual selection (`"+y`); Super+V
--                replaces selection with `+` (`"+p` after `d`).
--   - insert   : Super+V inserts `+` at cursor (`<C-r>+`); Super+C is a
--                no-op (you'd switch to visual to copy).
--   - terminal : leave defaults — terminal-mode is for sub-shells, not
--                vim-buffer text.
--
-- Ghostty also intercepts Ctrl+Shift+V at the terminal layer for paste
-- (bracketed paste). nvim's bracketed-paste handling treats that
-- correctly, so terminal-nvim Super+V pasting works WITHOUT this mapping
-- ever firing inside ghostty. The mapping below is what kicks in for
-- neovide and as a fallback.

-- Helper: try to map a key. Some terminfo setups don't recognise the
-- exact `<C-S-c>` form; the mapping is a no-op in those cases.
local map = vim.keymap.set

-- Copy
map({ "n" }, "<C-S-c>", '"+yy', { desc = "Copy line to system clipboard" })
map({ "v", "x" }, "<C-S-c>", '"+y', { desc = "Copy visual selection to system clipboard" })

-- Paste
map({ "n" }, "<C-S-v>", '"+p', { desc = "Paste from system clipboard (after cursor)" })
map({ "v", "x" }, "<C-S-v>", '"_d"+P', { desc = "Replace selection with system clipboard" })
map({ "i" }, "<C-S-v>", "<C-r>+", { desc = "Paste from system clipboard (insert mode)" })

-- Neovide also delivers Super-modified keys natively as <D-c>/<D-v> on
-- some platforms or <M-c>/<M-v> via its own keymap. The route-script
-- already translates Super+C/V to Ctrl+Shift+C/V before they reach
-- neovide, so the bindings above cover both paths.
