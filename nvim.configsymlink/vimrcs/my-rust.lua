-- Rust: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   rust-analyzer, clippy, rustfmt, rustaceanvim
-- Tools installed via Mason in mason.lua: codelldb (DAP config in nvim-dap.lua)
-- clippy runs as rust-analyzer check command (no nvim-lint needed)
-- rustfmt runs via rust-analyzer formatting (no external call needed)

-- LSP: rustaceanvim manages rust-analyzer (replaces lspconfig for Rust)
vim.g.rustaceanvim = {
  server = {
    settings = {
      ['rust-analyzer'] = {
        check = { command = 'clippy' },
      },
    },
  },
}

-- DAP: codelldb (shared adapter defined in nvim-dap.lua, Mason-installed)
require('dap').configurations.rust = require('dap').configurations.cpp
