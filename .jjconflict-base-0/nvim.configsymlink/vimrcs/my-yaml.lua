-- YAML: LSP, formatter
-- Tools installed via nix in nvim.nix:
--   yaml-language-server (yamlls), prettier
-- No DAP or standalone linter (yamlls provides diagnostics)

-- LSP: yamlls (yaml-language-server)
vim.lsp.config.yamlls = {}
vim.lsp.enable('yamlls')
