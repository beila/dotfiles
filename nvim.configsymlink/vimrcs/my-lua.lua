-- Lua: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: lua-language-server, selene, stylua

require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            runtime = { version = 'LuaJIT' },
            diagnostics = { globals = { 'vim' } },
            workspace = {
                checkThirdParty = false,
                library = vim.api.nvim_get_runtime_file('', true),
            },
        },
    },
})
