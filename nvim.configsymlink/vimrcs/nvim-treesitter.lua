local parser_dir = vim.fn.stdpath('data') .. '/treesitter'
vim.opt.runtimepath:append(parser_dir)

require 'nvim-treesitter.configs'.setup {
    parser_install_dir = parser_dir,
    ensure_installed = {},
    --[[ ensure_installed = {
        -- languages
        "awk", "bash", "c", "cmake", "cpp", "css", "csv", "diff", "dockerfile",
        "dot", "doxygen", "git_config", "git_rebase", "gitattributes", "gitcommit",
        "gitignore", "glsl", "gnuplot", "groovy", "haskell", "html", "htmldjango",
        "idl", "java", "javascript", "jinja", "json", "json5", "jsonc", "just",
        "kotlin", "lua", "make", "markdown", "nim", "ninja", "nix", "passwd",
        "perl", "proto", "python", "rst", "rust", "sql", "ssh_config", "toml",
        "typescript", "udev", "vim", "vimdoc", "xml", "yaml",
        -- injected/inline (not auto-installed)
        "angular", "asm", "comment", "fish", "glimmer", "graphql",
        "haskell_persistent", "jinja_inline", "jsdoc", "luadoc", "luap",
        "markdown_inline", "nim_format_string", "pod", "printf", "promql", "query",
        "re2c", "readline", "regex", "ruby", "slint", "styled",
    }, ]]
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

vim.keymap.set('n', '<C-w>', require('nvim-treesitter.incremental_selection').init_selection)
vim.keymap.set('v', '<C-w>', require('nvim-treesitter.incremental_selection').node_incremental)
vim.keymap.set('v', '<C-e>', require('nvim-treesitter.incremental_selection').node_decremental)
vim.keymap.set('v', '<C-d>', require('nvim-treesitter.incremental_selection').scope_incremental)

local ts_swap = require('nvim-treesitter.textobjects.swap')
vim.keymap.set('n', '<leader>a', function() ts_swap.swap_next('@parameter.inner') end)
vim.keymap.set('n', '<leader>A', function() ts_swap.swap_previous('@parameter.inner') end)
