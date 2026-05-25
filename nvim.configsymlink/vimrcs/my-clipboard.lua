-- Super+C / Super+V handling inside nvim. keyd's [meta] layer emits a
-- two-token macro: bare copy/paste (ghostty/firefox/GTK) + F24/F20 (neovide,
-- whose winit get_special_key drops bare XF86Copy/Paste). Both paths are
-- mapped below to identical mode-aware behaviour. yy/p keep the unnamed
-- register; only explicit Super+C/V crosses to `+`. Full chain in AGENTS.md
-- "Universal copy/paste".
--
-- Mode-aware behaviour (same for <F24>/<F20> and <XF86Copy>/<XF86Paste>):
--   visual   : copy = yank selection to +;  paste = `"_d"+P` (replace selection)
--   normal   : copy = yank <cword> to +;     paste = `"+P` (before cursor)
--   insert   : copy = yank <cword> to +;     paste = `<C-r>+`
--   command  : copy = yank cmdline to +;     paste = `<C-r>+`
--   terminal : copy = no-op;                 paste = `<C-\><C-n>"+pi`

local map = vim.keymap.set

-- Copy helpers, scoped per mode:
--   visual : `:yank +` (whole selection)
--   normal/insert : `<cword>` under the cursor (`expand("<cword>")`)
--   command : the entire command-line being typed (`getcmdline()`)
local function copy_visual()
  vim.api.nvim_cmd({ cmd = "yank", reg = "+" }, {})
end
local function copy_word()
  local w = vim.fn.expand("<cword>")
  if w ~= "" then
    vim.fn.setreg("+", w)
  end
end
local function copy_cmdline()
  local s = vim.fn.getcmdline()
  if s ~= "" then
    vim.fn.setreg("+", s)
  end
  -- return the same cmdline text so the command-line is unchanged after the mapping fires
  return s
end

-- <F24> / <F20> — neovide path. Command-mode copy is `expr = true` so
-- the function's return value (the unchanged cmdline text) replaces the
-- mapping output, keeping the cmdline intact while setreg("+", …) runs
-- as a side effect.
map("v", "<F24>", copy_visual, { silent = true, desc = "Copy visual selection to +" })
map({ "n", "i" }, "<F24>", copy_word, { silent = true, desc = "Copy <cword> to +" })
map("c", "<F24>", copy_cmdline, { silent = true, expr = true, desc = "Copy command-line to +" })

-- Paste — see the "Mode-aware behaviour" table at the top of this file.
map("n", "<F20>", '"+P', { silent = true, desc = "Paste before cursor (+ register)" })
map({ "v", "x" }, "<F20>", '"_d"+P', { silent = true, desc = "Replace selection with +" })
map("i", "<F20>", "<C-r>+", { silent = true, desc = "Insert + register" })
map("c", "<F20>", "<C-r>+", { silent = true, desc = "Insert + register into cmdline" })
map("t", "<F20>", [[<C-\><C-n>"+pi]], { silent = true, desc = "Paste + in terminal" })

-- <XF86Copy> / <XF86Paste> — fallback for any nvim host that delivers the
-- bare keysym directly (e.g. terminal nvim's insert mode via ghostty
-- bracketed paste, or a future nvim GUI that handles the keysym natively).
-- Mirrors the F24/F20 behaviour exactly so users don't have to remember
-- which keysym their host happens to pass through.
map("v", "<XF86Copy>", copy_visual, { silent = true, desc = "Copy visual selection to +" })
map({ "n", "i" }, "<XF86Copy>", copy_word, { silent = true, desc = "Copy <cword> to +" })
map("c", "<XF86Copy>", copy_cmdline, { silent = true, expr = true, desc = "Copy command-line to +" })

map("n", "<XF86Paste>", '"+P', { silent = true, desc = "Paste before cursor (+ register)" })
map({ "v", "x" }, "<XF86Paste>", '"_d"+P', { silent = true, desc = "Replace selection with +" })
map("i", "<XF86Paste>", "<C-r>+", { silent = true, desc = "Insert + register" })
map("c", "<XF86Paste>", "<C-r>+", { silent = true, desc = "Insert + register into cmdline" })
map("t", "<XF86Paste>", [[<C-\><C-n>"+pi]], { silent = true, desc = "Paste + in terminal" })
