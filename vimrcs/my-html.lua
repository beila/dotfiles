-- HTML: LSP, formatter
-- Tools installed via nix in nvim.nix:
--   vscode-langservers-extracted (provides html/css/json/eslint LSPs), prettier

require('lspconfig').html.setup({})
