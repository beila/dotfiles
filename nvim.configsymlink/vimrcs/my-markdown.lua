-- Markdown: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: marksman, markdownlint-cli2
-- Formatter: prettier — installed for html

require('lspconfig').marksman.setup({})

-- 테이블 편집이 편하도록 마크다운에서 자동 활성화 (<leader>tm 으로 토글)
vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    command = "silent! TableModeEnable",
})
