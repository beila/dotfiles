-- Nim: LSP
-- Tools installed via nix in nvim.nix: nimlangserver
-- Formatter: nimpretty (bundled with nim, install nim in home.nix if needed)

require('lspconfig').nim_langserver.setup({})
