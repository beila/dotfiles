-- harper-ls: offline grammar checker for prose (harper via nix, nvim.nix)
-- Division of labor: harper = grammar/typos, vale = style (nvim-lint.lua),
-- built-in :set spell = spelling with the en.utf-8.add allowlist.
-- Restricted to prose filetypes — lspconfig's default also lints comments in
-- code (lua, rust, nix, …), too noisy next to each language's own tooling.

vim.lsp.config.harper_ls = {
    filetypes = { 'text', 'markdown', 'gitcommit', 'rst', 'org', 'asciidoc', 'tex', 'mail' },
    settings = {
        ['harper-ls'] = {
            -- reuse vim's spell allowlist (zg) so both tools share one dictionary;
            -- harper's add-to-dictionary code action appends here, run :mkspell!
            -- afterwards for vim spell to see the new word
            userDictPath = vim.fn.stdpath('config') .. '/spell/en.utf-8.add',
            linters = {
                -- notes/TODO bullets here start lowercase by convention
                SentenceCapitalization = false,
            },
        },
    },
}
vim.lsp.enable('harper_ls')
