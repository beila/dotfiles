-- CMake: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: neocmakelsp, cmake-format, cmake-lint

-- LSP: neocmake (neocmakelsp — faster Rust-based alternative to cmake-language-server)
require('lspconfig').neocmake.setup({})

-- errorformat for CMake output
vim.opt.errorformat = table.concat({
    ' %#%f:%l %#(%m)',
    '%ECMake Error at %f:%l (message):',
    '%ZCall Stack (most recent call first):',
    '%C %m',
}, ',')

-- cmake-specific settings
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'cmake',
    callback = function()
        vim.opt_local.iskeyword:append('-')
        -- message(STATUS ...) debug helper
        vim.keymap.set('n', '<leader>C', function()
            local line = vim.api.nvim_get_current_line()
            local escaped = line:gsub('"', '\\"')
            local msg = ('message(STATUS "%s")    # FIXME'):format(escaped)
            local row = vim.api.nvim_win_get_cursor(0)[1]
            vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { msg })
        end, { buffer = true })
    end,
})
