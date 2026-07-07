-- Markdown: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: marksman, markdownlint-cli2
-- Formatter: prettier — installed for html
-- Spell check: built-in :set spell (see myvimrc) + spell/en.utf-8.add allowlist.
--   To spell-check from the CLI with the SAME allowlist, run `spellcheck-md FILE...`
--   (~/.dotfiles/bin/) — it wraps codespell with en.utf-8.add as --ignore-words.
--   Don't hand-roll aspell: it rejects digit-suffixed words (EC2, dup2) in the list.

vim.lsp.config.marksman = {}
vim.lsp.enable('marksman')

-- 테이블 편집이 편하도록 마크다운에서 자동 활성화 (<leader>tm 으로 토글)
vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    command = "silent! TableModeEnable",
})
