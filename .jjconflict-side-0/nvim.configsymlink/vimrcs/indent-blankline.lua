local hooks = require('ibl.hooks')

hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
  vim.api.nvim_set_hl(0, 'IblIndent', { fg = '#222222', nocombine = true })
  vim.api.nvim_set_hl(0, 'IblScope', { fg = '#666666', nocombine = true })
end)

require('ibl').setup {
  indent = { highlight = 'IblIndent' },
  scope = {
    enabled = true,
    highlight = 'IblScope',
    show_start = false,
    show_end = false,
    include = {
      node_type = {
        ['*'] = { '*' },
      },
    },
  },
}

-- Ensure all languages pass ibl's early scope check
local scope_lang = require('ibl.scope_languages')
setmetatable(scope_lang, {
  __index = function() return { ['*'] = true } end,
})

-- Force treesitter parse so ibl scope works immediately
vim.api.nvim_create_autocmd('FileType', {
  callback = function()
    vim.schedule(function()
      pcall(function() vim.treesitter.get_parser(0):parse() end)
      require('ibl').debounced_refresh(0)
    end)
  end,
})
