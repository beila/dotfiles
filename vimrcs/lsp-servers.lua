-- Per-server lspconfig setup
-- Nix-installed servers (not managed by mason-lspconfig handler)
require('lspconfig').awk_ls.setup({})

-- Mason-installed servers with custom config (override mason-lspconfig defaults)
require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
})
