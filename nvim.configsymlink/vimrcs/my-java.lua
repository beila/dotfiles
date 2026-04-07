-- Java: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   jdt-language-server, google-java-format, checkstyle
-- Tools installed via Mason in mason.lua:
--   java-debug-adapter (not in nixpkgs)

-- LSP: jdtls (jdt-language-server)
vim.lsp.config.jdtls = {
    cmd = { 'jdtls' },
}
vim.lsp.enable('jdtls')

-- DAP: java-debug-adapter (Mason-installed)
local dap = require('dap')
dap.configurations.java = {
    {
        name = 'Launch Java',
        type = 'java',
        request = 'launch',
    },
}
