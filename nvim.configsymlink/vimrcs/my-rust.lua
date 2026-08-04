-- Rust: LSP, DAP, linter, formatter
-- rust-analyzer comes from work-dotfiles, not nix. clippy and rustfmt come with
-- the Rust toolchain (rust-analyzer runs `cargo clippy` / rustfmt itself).
-- Tools installed via nix in nvim.nix:
--   rustaceanvim
-- Tools installed via Mason in mason.lua: codelldb (DAP config in nvim-dap.lua)
-- clippy runs as rust-analyzer check command (no nvim-lint needed)
-- rustfmt runs via rust-analyzer formatting (no external call needed)

-- LSP: rustaceanvim manages rust-analyzer (not via vim.lsp.config)
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
