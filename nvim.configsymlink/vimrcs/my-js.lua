-- JavaScript/TypeScript/JSX/TSX: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   typescript-language-server, vscode-js-debug, biome, prettier

-- LSP: ts_ls (typescript-language-server)
require('lspconfig').ts_ls.setup({})

-- Linter: biome (also an LSP, provides diagnostics)
require('lspconfig').biome.setup({})

-- DAP: vscode-js-debug (nix-installed)
local dap = require('dap')
dap.adapters['pwa-node'] = {
    type = 'server',
    host = 'localhost',
    port = '${port}',
    executable = {
        command = 'js-debug',
        args = { '${port}' },
    },
}
for _, ft in ipairs({ 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }) do
    dap.configurations[ft] = {
        {
            name = 'Launch file',
            type = 'pwa-node',
            request = 'launch',
            program = '${file}',
            cwd = '${workspaceFolder}',
        },
    }
end
