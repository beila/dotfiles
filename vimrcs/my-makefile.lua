-- Makefile: LSP, linter
-- Tools installed via nix in nvim.nix: autotools-language-server, checkmake

-- LSP: autotools_ls (autotools-language-server)
require('lspconfig').autotools_ls.setup({})
