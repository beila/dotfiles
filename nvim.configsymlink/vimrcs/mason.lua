-- Mason: auto-install DAPs (LSP servers installed via nix, configured in my-*.lua)
-- Coverage table and nix-installed tools are documented in nvim.nix

require('mason').setup({})

require('mason-lspconfig').setup({
    automatic_enable = false,
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
