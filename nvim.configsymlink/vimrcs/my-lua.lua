-- Lua: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: lua-language-server, selene, stylua

-- LSP: lua_ls (lua-language-server)
require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            runtime = { version = 'LuaJIT' },
            workspace = {
                library = vim.api.nvim_get_runtime_file('', true),
                checkThirdParty = false,
            },
        },
    },
})
