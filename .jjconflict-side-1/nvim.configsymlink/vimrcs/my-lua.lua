-- Lua: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: lua-language-server, selene, stylua

vim.lsp.config.lua_ls = {
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
}
vim.lsp.enable('lua_ls')
