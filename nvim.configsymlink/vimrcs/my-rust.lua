-- Rust: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   rust-analyzer, clippy, rustfmt
-- Tools installed via Mason in mason.lua: codelldb (DAP config in nvim-dap.lua)
-- clippy runs as rust-analyzer check command (no nvim-lint needed)
-- rustfmt runs via rust-analyzer formatting (no external call needed)

-- LSP: rust-analyzer (clippy as check command, rustfmt for formatting)
require('lspconfig').rust_analyzer.setup({
    settings = {
        ['rust-analyzer'] = {
            check = { command = 'clippy' },
        },
    },
})

-- DAP: codelldb (shared adapter defined in nvim-dap.lua, Mason-installed)
require('dap').configurations.rust = require('dap').configurations.cpp
