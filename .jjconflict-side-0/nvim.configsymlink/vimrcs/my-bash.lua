-- Bash/Zsh: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix: bash-language-server, shfmt
-- Tools installed via Mason in mason.lua: bash-debug-adapter
-- shellcheck installed via nix in home.nix

-- LSP: bashls (uses shellcheck for linting, shfmt for formatting when on $PATH)
vim.lsp.config.bashls = {
    filetypes = { 'sh', 'bash' },
    settings = {
        bashIde = {
            shellcheckPath = 'shellcheck',
            shfmt = { path = 'shfmt' },
        },
    },
}
vim.lsp.enable('bashls')

-- DAP: bash-debug-adapter (Mason-installed)
local dap = require('dap')
dap.adapters.bashdb = {
    type = 'executable',
    command = vim.fn.stdpath('data') .. '/mason/bin/bash-debug-adapter',
}
dap.configurations.sh = {
    {
        name = 'Launch Bash',
        type = 'bashdb',
        request = 'launch',
        program = function()
            return vim.fn.input('Script: ', vim.fn.expand('%:p'), 'file')
        end,
        cwd = '${workspaceFolder}',
        pathBashdb = vim.fn.stdpath('data') .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
        pathBashdbLib = vim.fn.stdpath('data') .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
        pathBash = 'bash',
        pathCat = 'cat',
        pathMkfifo = 'mkfifo',
        pathPkill = 'pkill',
        env = {},
        args = {},
    },
}
