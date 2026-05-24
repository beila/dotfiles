-- Super+C / Super+V handling inside nvim (primarily for neovide).
--
-- Setup chain (full path is documented in AGENTS.md "Universal copy/paste"):
--   1. keyd's [meta] layer in ~/.dotfiles/keyd/common emits a TWO-token
--      macro on Super+C / Super+V — bare `copy`/`paste` keysym FIRST (for
--      ghostty/firefox/GTK), then `f24`/`f20` SECOND (for neovide).
--   2. xmonad's startupHook runs `xmodmap -e 'keycode 198 = F20' -e
--      'keycode 202 = F24'` to override xkb's `inet` rules, which would
--      otherwise turn evdev F20/F24 into XF86AudioMicMute / unmapped at
--      the X11 layer (winit can't translate those into NamedKey::F20/F24).
--   3. winit recognises X11 keysyms F20/F24 → NamedKey::F20/F24; neovide's
--      `get_special_key` (src/window/keyboard_manager.rs) explicitly lists
--      F1–F35 → "F20"/"F24" strings, so they reach nvim as <F24>/<F20>.
--   4. The bare `copy`/`paste` keysym would map to NamedKey::Copy / Paste
--      at the winit layer, but those have no case in `get_special_key` and
--      fall through to `_ => None` — silently dropped by neovide.
--
-- That's why neovide listens on <F24>/<F20> while ghostty/firefox/GTK
-- listen on the bare keysyms; each app reacts to whichever it's bound to
-- and ignores the other. Both paths are mapped below to identical mode-
-- aware behaviour so the user doesn't have to think about which keysym
-- their host happens to deliver.
--
-- Why F24/F20 specifically: F21–F23 are already taken by prog1/2/3
-- (Albert / scratchpads) via keyd v2.6.0. KEY_F24 (194) is the kernel
-- F-key ceiling — winit lists F25–F35 in its NamedKey enum but they don't
-- exist at the evdev layer. F20 is the next free slot below the prog
-- range.
--
-- Why not Super+letter directly: neovide does serialize Super as `<D-c>`
-- / `<D-v>` per its official FAQ, but on Linux GNOME-shell intercepts
-- `<Super>v` for toggle-message-tray before any app sees it (we strip
-- that binding in gnome.nix). And more generally, Super-modified letters
-- are fragile across desktop environments / compositors. F-keys sidestep
-- all modifier-handling quirks.
--
-- Why not `set clipboard=unnamedplus`: the user wants `yy`/`p` to keep
-- using the unnamed register, not the system clipboard. Only explicit
-- Super+C/V crosses to `+`.
--
-- Mode-aware behaviour (identical for both <F24>/<F20> and <XF86Copy>/<XF86Paste>):
--   visual   : copy = yank selection to +;  paste = `"_d"+P` (replace selection)
--   normal   : copy = yank <cword> to +;     paste = `"+P` (before cursor)
--   insert   : copy = yank <cword> to +;     paste = `<C-r>+`
--   command  : copy = yank cmdline to +;     paste = `<C-r>+`
--   terminal : copy = (no-op);               paste = `<C-\><C-n>"+pi` (drop to normal, paste, re-enter insert)

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
