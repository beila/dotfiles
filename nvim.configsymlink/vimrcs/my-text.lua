-- Text: linter
-- Tools installed via nix in nvim.nix: vale
-- No LSP, DAP, or formatter for plain text
-- vale linting configured in nvim-lint.lua

vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
    pattern = "log-*.txt",
    command = "setlocal filetype=log",
})

-- Dim paragraphs away from the cursor. Adjacent paragraphs get a lighter dim than the others.
require("paragraph-dim").setup({ text=1, markdown=1, rst=1, org=1, asciidoc=1, tex=1, mail=1, gitcommit=1 })
