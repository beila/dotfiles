local parser_dir = vim.fn.stdpath('data') .. '/treesitter'
vim.opt.runtimepath:append(parser_dir)

-- nvim-treesitter.configs was removed in nvim-treesitter 1.0 (nvim 0.12)
-- Try new API first, fall back to old
local ok, configs = pcall(require, 'nvim-treesitter.configs')
if ok and configs.setup then
    configs.setup {
        parser_install_dir = parser_dir,
        ensure_installed = {},
        auto_install = false,
        highlight = { enable = true, },
        indent = { enable = true, },
        incremental_selection = {
            enable = true,
            keymaps = {
                init_selection = false,
                node_incremental = false,
                node_decremental = false,
            },
        },
        textobjects = {
            select = {
                enable = true,
                lookahead = true,
                keymaps = {
                    ['af'] = '@function.outer',
                    ['if'] = '@function.inner',
                    ['ac'] = '@class.outer',
                    ['ic'] = '@class.inner',
                    ['aa'] = '@parameter.outer',
                    ['ia'] = '@parameter.inner',
                },
            },
            move = {
                enable = true,
                set_jumps = true,
                goto_next_start = {
                    [']f'] = '@function.outer',
                    [']a'] = '@parameter.outer',
                },
                goto_previous_start = {
                    ['[f'] = '@function.outer',
                    ['[a'] = '@parameter.outer',
                },
            },
            swap = {
                enable = true,
                swap_next = {
                    ['<leader>a'] = '@parameter.inner',
                },
                swap_previous = {
                    ['<leader>A'] = '@parameter.inner',
                },
            },
        },
    }
else
    -- New nvim-treesitter: highlight/indent are built-in, just set parser dir
    pcall(function()
        require('nvim-treesitter.config').setup { install_dir = parser_dir }
    end)
end

-- Incremental selection keymaps
local ok_inc, inc = pcall(require, 'nvim-treesitter.incremental_selection')
if ok_inc then
    vim.keymap.set('n', '<C-e>', inc.init_selection)
    vim.keymap.set('v', '<C-e>', inc.node_incremental)
    vim.keymap.set('v', '<C-d>', inc.node_decremental)
end

-- Swap keymaps
local ok_swap, ts_swap = pcall(require, 'nvim-treesitter.textobjects.swap')
if ok_swap then
    vim.keymap.set('n', '<leader>a', function() ts_swap.swap_next('@parameter.inner') end)
    vim.keymap.set('n', '<leader>A', function() ts_swap.swap_previous('@parameter.inner') end)
end
