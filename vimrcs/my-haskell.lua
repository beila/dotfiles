-- Haskell: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   haskell-language-server, fourmolu, hlint
-- Tools installed via Mason in mason.lua:
--   haskell-debug-adapter (not in nixpkgs)

-- LSP: hls (uses fourmolu for formatting, hlint for hints)
require('lspconfig').hls.setup({
    filetypes = { 'haskell', 'lhaskell', 'cabal' },
    settings = {
        haskell = {
            formattingProvider = 'fourmolu',
        },
    },
})
