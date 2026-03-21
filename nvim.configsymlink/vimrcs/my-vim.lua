-- Vimscript: LSP, linter
-- Tools installed via nix in nvim.nix:
--   vim-language-server (vimls), vim-vint (vint, tests disabled)
-- No DAP or formatter for Vimscript
-- vint linting configured in nvim-lint.lua

-- LSP: vimls (vim-language-server)
require('lspconfig').vimls.setup({})
