-- Jinja: LSP, linter/formatter
-- Tools installed via nix in nvim.nix: jinja-lsp, djlint

-- filetype detection
vim.filetype.add({
    extension = {
        jinja = 'jinja',
        jinja2 = 'jinja',
        j2 = 'jinja',
    },
})

-- LSP: jinja_lsp
vim.lsp.config.jinja_lsp = {}
vim.lsp.enable('jinja_lsp')
