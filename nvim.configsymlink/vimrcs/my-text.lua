-- Text: linter
-- Tools installed via nix in nvim.nix: vale
-- No LSP, DAP, or formatter for plain text
-- vale linting configured in nvim-lint.lua

vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
    pattern = "log-*.txt",
    command = "setlocal filetype=log",
})

local limelight_fts = { text=1, markdown=1, rst=1, org=1, asciidoc=1, tex=1, mail=1, gitcommit=1 }

vim.api.nvim_create_autocmd({"BufEnter", "FileType"}, {
    callback = function()
        if limelight_fts[vim.bo.filetype] then
            vim.cmd("silent! Limelight")
        else
            vim.cmd("silent! Limelight!")
        end
    end,
})
