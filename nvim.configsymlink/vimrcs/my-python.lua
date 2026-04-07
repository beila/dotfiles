-- Python: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: basedpyright, ruff
-- Tools installed via Mason in mason.lua: debugpy (not in nixpkgs)

-- LSP: basedpyright (stricter fork of pyright)
vim.lsp.config.basedpyright = {}
vim.lsp.enable('basedpyright')

-- Linter+formatter: ruff (also an LSP, provides diagnostics + formatting)
vim.lsp.config.ruff = {}
vim.lsp.enable('ruff')

-- DAP: debugpy via nvim-dap-python plugin (Mason-installed)
require("dap-python").setup("uv")
