-- Docker: LSP, linter
-- Tools installed via nix in nvim.nix:
--   dockerfile-language-server-nodejs, docker-compose-language-service, hadolint

-- LSP: dockerls
vim.lsp.config.dockerls = {}
vim.lsp.enable('dockerls')

-- LSP: docker-compose
vim.lsp.config.docker_compose_language_service = {}
vim.lsp.enable('docker_compose_language_service')
