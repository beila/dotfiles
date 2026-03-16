-- Markdown: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: marksman, markdownlint-cli2
-- Formatter: prettier — installed for html

require('lspconfig').marksman.setup({})
