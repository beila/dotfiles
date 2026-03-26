-- Text: linter
-- Tools installed via nix in nvim.nix: vale
-- No LSP, DAP, or formatter for plain text
-- vale linting configured in nvim-lint.lua

vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
    pattern = "log-*.txt",
    command = "setlocal filetype=log",
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "text", "markdown", "rst", "org", "asciidoc", "tex", "mail", "gitcommit" },
    callback = function(ev)
        vim.b[ev.buf].limelight = true
        vim.cmd("Limelight")
    end,
})

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
        if vim.b[ev.buf].limelight then
            vim.cmd("Limelight")
        else
            vim.cmd("silent! Limelight!")
        end
    end,
})

vim.api.nvim_create_autocmd("BufLeave", {
    callback = function()
        vim.cmd("silent! Limelight!")
    end,
})
