-- TOML: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: taplo
-- No DAP for TOML
-- taplo provides LSP diagnostics (linter) and formatting in one

-- LSP: taplo (includes validation + formatting)
require('lspconfig').taplo.setup({})
