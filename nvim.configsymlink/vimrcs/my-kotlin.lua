-- Kotlin: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: kotlin-language-server, ktlint
-- Tools installed via Mason in mason.lua: kotlin-debug-adapter (not in nixpkgs)

-- LSP: kotlin_language_server
-- storagePath must be a non-nil string: lspconfig's default sets it from
-- vim.fs.root(), which is nil outside a project, leaving init_options an empty
-- table that serializes to JSON [] and crashes the server on init
-- (getStoragePath: "Expected BEGIN_OBJECT but was BEGIN_ARRAY").
vim.lsp.config.kotlin_language_server = {
    init_options = {
        storagePath = vim.fn.stdpath('cache'),
    },
}
vim.lsp.enable('kotlin_language_server')

-- DAP: kotlin-debug-adapter (Mason-installed)
local dap = require('dap')
dap.adapters.kotlin = {
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/kotlin-debug-adapter',
}
dap.configurations.kotlin = {
    {
        name = 'Launch Kotlin',
        type = 'kotlin',
        request = 'launch',
        projectRoot = '${workspaceFolder}',
        mainClass = function()
            return vim.fn.input('Main class: ')
        end,
    },
}
