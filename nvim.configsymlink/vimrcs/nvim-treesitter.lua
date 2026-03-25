local parser_dir = vim.fn.stdpath('data') .. '/treesitter'
vim.opt.runtimepath:append(parser_dir)

require 'nvim-treesitter.configs'.setup {
    parser_install_dir = parser_dir,
    ensure_installed = {
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
    },
    auto_install = false,
    highlight = { enable = true, },
    indent = { enable = true, },
    incremental_selection = {
        enable = true,
        keymaps = {
            init_selection = '<c-e>',
            node_incremental = '<c-e>',
            node_decremental = '<c-r>',
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
