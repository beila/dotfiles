-- nvim-lint: run external linters as neovim diagnostics
-- Only linters NOT already handled by their LSP are listed here
-- (e.g. bashls already runs shellcheck, HLS already runs hlint)

local lint = require('lint')

lint.linters_by_ft = {
    cmake = { 'cmake_lint' },
    dockerfile = { 'hadolint' },
    java = { 'checkstyle' },
    make = { 'checkmake' },
    markdown = { 'markdownlint-cli2', 'vale' },
    nix = { 'statix', 'deadnix' },
    sql = { 'sqlfluff' },
    vim = { 'vint' },
}

-- vale (style linter) on every prose filetype — pairs with harper_ls (grammar,
-- see harper.lua) and built-in :set spell (spelling). Vale parses md/rst/etc
-- natively via the buffer's extension; gitcommit/mail have no extension so it
-- falls back to plain text, which is fine. markdown keeps markdownlint-cli2 too.
for _, ft in ipairs({ 'text', 'rst', 'asciidoc', 'tex', 'org', 'mail', 'gitcommit' }) do
    lint.linters_by_ft[ft] = { 'vale' }
end

-- markdownlint-cli2 only auto-discovers config in the exact cwd when fed via
-- stdin (which nvim-lint does), so ~/.markdownlint-cli2.yaml is ignored unless
-- the file happens to sit in $HOME. Pass it explicitly so line-length:false etc. apply.
local md_config = vim.fn.expand('~/.markdownlint-cli2.yaml')
if vim.uv.fs_stat(md_config) then
    lint.linters['markdownlint-cli2'].args = { '--config', md_config, '-' }
end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
    callback = function() require('lint').try_lint() end,
})
