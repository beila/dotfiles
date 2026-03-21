-- Text: linter
-- Tools installed via nix in nvim.nix: vale
-- No LSP, DAP, or formatter for plain text
-- vale linting configured in nvim-lint.lua

vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
    pattern = "log-*.txt",
    command = "setlocal filetype=log",
})
