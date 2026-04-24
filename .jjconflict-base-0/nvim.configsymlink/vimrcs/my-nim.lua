-- Nim: LSP
-- Tools installed via nix in nvim.nix: nimlangserver
-- Formatter: nimpretty (bundled with nim, install nim in home.nix if needed)

vim.lsp.config.nim_langserver = {}
vim.lsp.enable('nim_langserver')
