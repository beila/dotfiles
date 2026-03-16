-- Just: LSP, formatter
-- Tools installed via nix in nvim.nix: just-lsp
-- Formatter: `just --fmt` (just installed in home.nix)

-- LSP: just-lsp (not in nvim-lspconfig, manual config)
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'just',
    callback = function()
        vim.lsp.start({
            name = 'just-lsp',
            cmd = { 'just-lsp' },
            root_dir = vim.fs.root(0, { 'justfile', '.justfile', '.git' }),
        })
    end,
})
