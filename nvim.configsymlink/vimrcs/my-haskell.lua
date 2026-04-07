-- Haskell: LSP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   haskell-language-server, fourmolu, hlint
-- DAP: haskell-debug-adapter — not in nixpkgs, broken in mason

-- LSP: hls (uses fourmolu for formatting, hlint for hints)
vim.lsp.config.hls = {
    filetypes = { 'haskell', 'lhaskell', 'cabal' },
    settings = {
        haskell = {
            formattingProvider = 'fourmolu',
        },
    },
}
vim.lsp.enable('hls')
