-- C/C++: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: clangd, clang-format (clang-tools), cppcheck
-- Tools installed via Mason in mason.lua: codelldb (DAP config in nvim-dap.lua)

-- LSP: clangd (nix-installed via clang-tools in nvim.nix)
require('lspconfig').clangd.setup({})

-- printf debug helper
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'cpp',
    callback = function()
        vim.keymap.set('n', '<leader>C', function()
            local line = vim.api.nvim_get_current_line()
            local escaped = line:gsub('"', '\\"')
            local printf = ('printf("%s\\n");    // FIXME'):format(escaped)
            local row = vim.api.nvim_win_get_cursor(0)[1]
            vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { printf })
        end, { buffer = true })
    end,
})
