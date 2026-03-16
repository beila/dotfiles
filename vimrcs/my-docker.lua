-- Docker: LSP, linter
-- Tools installed via nix in nvim.nix:
--   dockerfile-language-server-nodejs, docker-compose-language-service, hadolint

-- LSP: dockerls
require('lspconfig').dockerls.setup({})

-- LSP: docker-compose
require('lspconfig').docker_compose_language_service.setup({})
