-- Mason: auto-install LSP servers, DAPs, linters, formatters
-- Coverage table and nix-installed tools are documented in nvim.nix
-- Nix-installed tools with custom config: see my-*.lua and lsp-servers.lua

require('mason').setup({})

require('mason-lspconfig').setup({
    ensure_installed = {
    },
    handlers = {
        function(server_name)
            local server = require('lspconfig')[server_name]
            if server.setup then
                server.setup({})
            end
        end,
    },
})

require("mason-tool-installer").setup({
    ensure_installed = {
        -- DAP
        "bash-debug-adapter",    -- bash (DAP config in my-zsh.lua)
        "codelldb",              -- c/c++/rust (DAP config in nvim-dap.lua)
    },
})
