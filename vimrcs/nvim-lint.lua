-- nvim-lint: run external linters as neovim diagnostics
-- Only linters NOT already handled by their LSP are listed here
-- (e.g. bashls already runs shellcheck, HLS already runs hlint)

require('lint').linters_by_ft = {
    cmake = { 'cmake_lint' },
    dockerfile = { 'hadolint' },
    java = { 'checkstyle' },
    make = { 'checkmake' },
    markdown = { 'markdownlint' },
    nix = { 'statix', 'deadnix' },
    sql = { 'sqlfluff' },
    text = { 'vale' },
    vim = { 'vint' },
}

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
    callback = function() require('lint').try_lint() end,
})
