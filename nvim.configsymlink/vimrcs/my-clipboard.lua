-- Super+C / Super+V handling inside nvim (primarily for neovide).
--
-- Setup chain: keyd's [meta] layer (~/.dotfiles/keyd/common) emits a TWO-token
-- macro on Super+C / Super+V — first the bare `copy`/`paste` keysym (handled
-- by ghostty/firefox/GTK), then F24/F20 respectively. The F-keys are the
-- vehicle that reaches nvim inside neovide:
--   - The bare `copy`/`paste` keysym is silently dropped by neovide because
--     its `get_special_key` table (src/window/keyboard_manager.rs) has no
--     NamedKey::Copy / NamedKey::Paste case.
--   - F24/F20 ARE in that table (NamedKey::F20 / F24 → "F20" / "F24"), so
--     they survive neovide's pipeline and arrive as <F24> / <F20>.
--   - Neither F-key has a default binding in xmonad / GNOME / ghostty /
--     firefox, so the firefox/ghostty path only acts on the bare keysym
--     and ignores the F-key (and vice versa for neovide).
--
-- Why F24/F20 and not e.g. F21–F23: prog1/2/3 (Albert / scratchpads) are
-- already mapped to F21/F22/F23 by keyd v2.6.0. F24 is the highest standard
-- F-key on Linux (KEY_F24 = 194 — winit lists F25–F35 but they don't exist
-- at the evdev layer). F20 is the next free slot below the prog range.
--
-- Why not Super+letter directly: neovide does encode Super as `<D-c>`/`<D-v>`
-- (per the official FAQ recipe), but on Linux GNOME-shell intercepts
-- `<Super>v` for toggle-message-tray (we strip that in gnome.nix), and the
-- general approach of relying on Super-modified letters is fragile across
-- desktop environments. F-keys sidestep all modifier-handling differences.
--
-- Why not `set clipboard=unnamedplus`: the user wants `yy`/`p` to keep
-- using register 0, not the system clipboard. Only Super+C/V crosses to `+`.
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

-- <F24> / <F20> — keyd's neovide-friendly Super+C / Super+V vehicle.
map("v", "<F24>", copy, { silent = true, desc = "Copy visual selection to + register" })
map({ "n", "i", "v", "c", "t" }, "<F20>", paste, { silent = true, desc = "Paste from + register" })

-- <XF86Copy> / <XF86Paste> — fallback for any nvim host that delivers the
-- bare keysym (terminal nvim's insert mode via ghostty bracketed paste).
map("n", "<XF86Copy>", '"+yy', { desc = "Copy line to + register" })
map({ "v", "x" }, "<XF86Copy>", '"+y', { desc = "Copy visual selection to + register" })
map("n", "<XF86Paste>", '"+p', { desc = "Paste after cursor" })
map({ "v", "x" }, "<XF86Paste>", '"_d"+P', { desc = "Replace selection with +" })
map("i", "<XF86Paste>", "<C-r>+", { desc = "Paste from + register (insert mode)" })
map("c", "<XF86Paste>", "<C-r>+", { desc = "Paste from + register (command-line)" })
