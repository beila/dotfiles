-- Just: LSP, formatter
-- Tools installed via nix in nvim.nix: just-lsp
-- Formatter: `just --fmt` (just installed in home.nix)

-- LSP: just-lsp (manual config, not in default server list)
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'just',
    callback = function()
        vim.lsp.start({
            name = 'just-lsp',
            cmd = { 'just-lsp' },
            root_dir = vim.fs.root(0, { 'justfile', '.justfile', '.git' }),
        })
        -- Formatter: just --fmt (overrides <leader>af from lsp.lua)
        vim.keymap.set({ 'n', 'v' }, '<leader>af', function()
            vim.cmd('silent !just --fmt --justfile ' .. vim.fn.shellescape(vim.api.nvim_buf_get_name(0)))
            vim.cmd('edit')
        end, { buffer = true })
    end,
})
