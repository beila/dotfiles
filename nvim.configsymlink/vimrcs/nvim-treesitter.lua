-- Treesitter: all grammars installed via nix (nvim-treesitter.withAllGrammars)
-- highlight/indent are built-in in nvim 0.12

-- Swap parameters
require("nvim-treesitter-textobjects").setup({
  swap = {
    swap_next = { ["<leader>a"] = "@parameter.inner" },
    swap_previous = { ["<leader>A"] = "@parameter.inner" },
  },
})

-- Incremental selection (expand/shrink by treesitter node)
vim.keymap.set('n', '<C-e>', function()
  local node = vim.treesitter.get_node()
  if not node then return end
  local sr, sc, er, ec = node:range()
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { er + 1, ec - 1 })
end)

vim.keymap.set('v', '<C-e>', function()
  local node = vim.treesitter.get_node()
  if not node then return end
  local parent = node:parent()
  if not parent then return end
  local sr, sc, er, ec = parent:range()
  vim.cmd('normal! \27') -- exit visual
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { er + 1, ec - 1 })
end)

vim.keymap.set('v', '<C-d>', function()
  local node = vim.treesitter.get_node()
  if not node then return end
  -- Find the smallest child that still contains the cursor
  for child in node:iter_children() do
    if child:named() then
      local sr, sc, er, ec = child:range()
      vim.cmd('normal! \27')
      vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
      vim.cmd('normal! v')
      vim.api.nvim_win_set_cursor(0, { er + 1, ec - 1 })
      return
    end
  end
end)
