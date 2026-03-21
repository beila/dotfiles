-- Python: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: basedpyright, ruff
-- Tools installed via Mason in mason.lua: debugpy (not in nixpkgs)

-- LSP: basedpyright (stricter fork of pyright)
require('lspconfig').basedpyright.setup({})

-- Linter+formatter: ruff (also an LSP, provides diagnostics + formatting)
require('lspconfig').ruff.setup({})

-- DAP: debugpy via nvim-dap-python plugin (Mason-installed)
require("dap-python").setup("uv")
