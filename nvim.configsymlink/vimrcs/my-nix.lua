-- Nix: LSP, linter, formatter
-- Tools installed via nix in nvim.nix: nixd, statix, deadnix, nixfmt

-- LSP: nixd (feature-rich, evaluates nixpkgs for completions)
vim.lsp.config.nixd = {}
vim.lsp.enable('nixd')
