-- Kotlin: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: kotlin-language-server, ktlint
-- Tools installed via Mason in mason.lua: kotlin-debug-adapter (not in nixpkgs)

-- LSP: kotlin_language_server
vim.lsp.config.kotlin_language_server = {}
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
