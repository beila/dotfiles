-- CSS: LSP, formatter
-- Tools installed via nix in nvim.nix:
--   vscode-langservers-extracted (cssls, shared with html/json), prettier
-- No DAP or standalone linter (cssls provides diagnostics)

-- LSP: cssls (vscode-langservers-extracted, shared with html/json)
require('lspconfig').cssls.setup({})
