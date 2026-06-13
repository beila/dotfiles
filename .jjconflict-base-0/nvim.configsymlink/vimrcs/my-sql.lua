-- SQL: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: sqls, sqlfluff
-- No DAP for SQL
-- sqlfluff serves as both linter (via nvim-lint) and formatter

-- LSP: sqls
vim.lsp.config.sqls = {}
vim.lsp.enable('sqls')
