-- Per-server lspconfig setup
-- Nix-installed servers: see my-*.lua files

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
