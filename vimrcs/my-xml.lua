-- XML: LSP (includes linting + formatting)
-- Tools installed via nix in nvim.nix: lemminx

-- LSP: lemminx (Eclipse XML LSP, provides validation + formatting)
require('lspconfig').lemminx.setup({})
