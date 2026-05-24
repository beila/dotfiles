-- Super+C / Super+V handling inside nvim (primarily for neovide).
--
-- Setup chain: keyd remaps Super+C/V at the kernel/evdev layer to bare
-- XF86Copy / XF86Paste keysyms (see ~/.dotfiles/keyd/common's [meta] block).
-- Apps receive a clean keysym with no Super held, so the mapping below fires
-- reliably on the first press in neovide.
--
-- Where this matters:
--   - **neovide** (GUI nvim) — has focus directly; XF86Copy/XF86Paste
--     reach nvim. The mappings below fire and act on the `+` register.
--   - **terminal nvim inside ghostty** — ghostty INTERCEPTS XF86Paste
--     (its default `keybind = paste=paste_from_clipboard`) and sends
--     bracketed paste to nvim. That works in **insert mode only** (vim's
--     bracketed-paste handler inserts at cursor). For normal/visual
--     mode in terminal-nvim, use `"+y` / `"+p` directly — the mappings
--     below never fire there because ghostty already swallowed the key.
--
-- Why not `set clipboard=unnamedplus`?
-- The user explicitly wants the unnamed register to stay independent —
-- `yy` and `p` keep using register 0, not the system clipboard. Only
-- explicit Super+C/V (= XF86Copy / XF86Paste) crosses over to `+`.
--
-- Behaviour by mode (when the keystroke actually reaches nvim, i.e.
-- neovide always; terminal-nvim only in insert mode after ghostty's
-- bracketed-paste passthrough):
--   - normal   : Super+C copies the line under cursor (`"+yy`); Super+V
--                pastes from `+` after cursor (`"+p`).
--   - visual   : Super+C copies the visual selection (`"+y`); Super+V
--                replaces selection with `+` (`"_d"+P`).
--   - insert   : Super+V inserts `+` at cursor (`<C-r>+`); Super+C is a
--                no-op (switch to visual to copy).
--   - terminal : leave defaults.

local map = vim.keymap.set

-- Copy
map({ "n" }, "<XF86Copy>", '"+yy', { desc = "Copy line to system clipboard" })
map({ "v", "x" }, "<XF86Copy>", '"+y', { desc = "Copy visual selection to system clipboard" })

-- Paste
map({ "n" }, "<XF86Paste>", '"+p', { desc = "Paste from system clipboard (after cursor)" })
map({ "v", "x" }, "<XF86Paste>", '"_d"+P', { desc = "Replace selection with system clipboard" })
map({ "i" }, "<XF86Paste>", "<C-r>+", { desc = "Paste from system clipboard (insert mode)" })
