-- Mason: auto-install DAPs (LSP servers installed via nix, configured in my-*.lua)
-- Coverage table and nix-installed tools are documented in nvim.nix

require('mason').setup({})

require('mason-lspconfig').setup({
    ensure_installed = {
    },
    handlers = {
        function(server_name)
            -- Skip servers with custom config in my-*.lua
            if server_name == 'lua_ls' then return end
            vim.lsp.config[server_name] = {}
            vim.lsp.enable(server_name)
        end,
    },
})

require("mason-tool-installer").setup({
    ensure_installed = {
        -- DAP
        "bash-debug-adapter",    -- bash (DAP config in my-zsh.lua)
        "codelldb",              -- c/c++/rust (DAP config in nvim-dap.lua + my-rust.lua)
        "kotlin-debug-adapter",  -- kotlin (not in nixpkgs, DAP config in my-kotlin.lua)
        "java-debug-adapter",    -- java (not in nixpkgs, DAP config in my-java.lua)
        "debugpy",               -- python (not in nixpkgs, DAP config in my-python.lua)
    },
})
