-- Super+C / Super+V handling inside nvim (primarily for neovide).
--
-- Setup chain: keyd's [meta] layer (~/.dotfiles/keyd/common) emits a TWO-token
-- macro on Super+C / Super+V — first the bare `copy`/`paste` keysym (handled
-- by ghostty/firefox/GTK), then a real `M-c`/`M-v` (Super+letter, which
-- neovide's winit input layer reports to nvim as `<D-c>` / `<D-v>` per the
-- official FAQ recipe). Apps respond to whichever keysym they're bound to;
-- the other is silently dropped.
--
-- Why both keystrings:
--   - **neovide**: drops the bare XF86Copy/XF86Paste keysym (its
--     `get_special_key` table has no NamedKey::Copy / Paste case), so we need
--     the `<D-c>`/`<D-v>` path. Working in all modes (n/i/v/c/t).
--   - **terminal nvim inside ghostty**: ghostty intercepts XF86Paste before
--     nvim sees it (`keybind = paste=paste_from_clipboard`) and sends
--     bracketed paste — works in insert mode only. Normal/visual still
--     requires explicit `"+y`/`"+p`. The legacy `<XF86Paste>` mapping below
--     is kept for the rare case ghostty doesn't intercept (and as a no-op
--     fallback if neovide ever adds NamedKey::Paste support).
--
-- Why not `set clipboard=unnamedplus`?
-- The user explicitly wants the unnamed register to stay independent —
-- `yy` and `p` keep using register 0, not the system clipboard. Only
-- explicit Super+C/V crosses over to `+`.
--
-- Mappings follow Neovide's official FAQ
-- (https://neovide.dev/faq.html — "How can I use cmd-c/cmd-v…"), which
-- uses `vim.api.nvim_paste` for paste so it handles all modes uniformly.

local map = vim.keymap.set

local function copy()
  vim.api.nvim_cmd({ cmd = "yank", reg = "+" }, {})
end
local function paste()
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end

-- <D-c> / <D-v> — neovide's serialization of Super+C / Super+V on Linux.
map("v", "<D-c>", copy, { silent = true, desc = "Copy visual selection to + register" })
map({ "n", "i", "v", "c", "t" }, "<D-v>", paste, { silent = true, desc = "Paste from + register" })

-- <XF86Copy> / <XF86Paste> — fallback for any nvim host that delivers the
-- bare keysym (terminal nvim's insert mode via ghostty bracketed paste).
map("n", "<XF86Copy>", '"+yy', { desc = "Copy line to + register" })
map({ "v", "x" }, "<XF86Copy>", '"+y', { desc = "Copy visual selection to + register" })
map("n", "<XF86Paste>", '"+p', { desc = "Paste after cursor" })
map({ "v", "x" }, "<XF86Paste>", '"_d"+P', { desc = "Replace selection with +" })
map("i", "<XF86Paste>", "<C-r>+", { desc = "Paste from + register (insert mode)" })
map("c", "<XF86Paste>", "<C-r>+", { desc = "Paste from + register (command-line)" })
