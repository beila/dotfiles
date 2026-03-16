-- Systemd: LSP
-- Tools installed via nix in nvim.nix: systemd-language-server
-- No DAP, linter, or formatter for systemd unit files
-- Not in nvim-lspconfig; configured manually via vim.lsp.start

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'systemd',
    callback = function()
        vim.lsp.start({
            name = 'systemd-language-server',
            cmd = { 'systemd-language-server' },
            root_dir = vim.fs.root(0, { '.git' }) or vim.fn.getcwd(),
        })
    end,
})
