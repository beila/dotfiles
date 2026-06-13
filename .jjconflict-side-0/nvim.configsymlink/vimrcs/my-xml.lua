-- XML: LSP (includes linting + formatting)
-- Tools installed via nix in nvim.nix: lemminx

-- LSP: lemminx (Eclipse XML LSP, provides validation + formatting)
vim.lsp.config.lemminx = {}
vim.lsp.enable('lemminx')
