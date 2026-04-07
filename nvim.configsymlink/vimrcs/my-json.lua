-- JSON: LSP, formatter
-- Tools installed via nix in nvim.nix:
--   vscode-langservers-extracted (provides jsonls) — installed for html in my-html.lua
--   prettier — installed for html in my-html.lua

vim.lsp.config.jsonls = {}
vim.lsp.enable('jsonls')
