-- Treesitter: all grammars installed via nix (nvim-treesitter.withAllGrammars)
-- highlight/indent are built-in in nvim 0.12

-- Swap parameters
local swap = require("nvim-treesitter-textobjects.swap")
vim.keymap.set("n", "<leader>a", function() swap.swap_next("@parameter.inner") end)
vim.keymap.set("n", "<leader>A", function() swap.swap_previous("@parameter.inner") end)

-- Incremental selection (expand/shrink by treesitter node)
local sel_node = nil

vim.keymap.set('n', '<C-e>', function()
  sel_node = vim.treesitter.get_node()
  if not sel_node then return end
  local sr, sc, er, ec = sel_node:range()
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { er + 1, ec > 0 and ec - 1 or 0 })
end)

vim.keymap.set('v', '<C-e>', function()
  if sel_node then sel_node = sel_node:parent() end
  if not sel_node then return end
  local sr, sc, er, ec = sel_node:range()
  vim.cmd('normal! \27')
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { er + 1, ec > 0 and ec - 1 or 0 })
end)

vim.keymap.set('v', '<C-d>', function()
  if not sel_node then return end
  for child in sel_node:iter_children() do
    if child:named() then
      sel_node = child
      local sr, sc, er, ec = sel_node:range()
      vim.cmd('normal! \27')
      vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
      vim.cmd('normal! v')
      vim.api.nvim_win_set_cursor(0, { er + 1, ec > 0 and ec - 1 or 0 })
      return
    end
  end
end)
