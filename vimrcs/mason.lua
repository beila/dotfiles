-- Mason: auto-install LSP servers, DAPs, linters, formatters
-- Coverage table and nix-installed tools are documented in nvim.nix

require('mason').setup({})

require('mason-lspconfig').setup({
    ensure_installed = {
        "bashls",          -- bash/zsh
        "clangd",          -- c/c++
        "cmake",           -- cmake
        "dockerls",        -- docker
        "docker_compose_language_service", -- docker-compose
        "glsl_analyzer",   -- glsl/opengl
        "hls",             -- haskell
        "html",            -- html/jinja/nunjucks
        "jsonls",          -- json
        "ts_ls",           -- javascript/jsx/typescript
        "jqls",            -- jq
        "kotlin_language_server", -- kotlin
        "marksman",        -- markdown
        "nimls",           -- nim
        "nil_ls",          -- nix
        "pyright",         -- python
        "rust_analyzer",   -- rust
        "sqlls",           -- sql
        "taplo",           -- toml
        "vimls",           -- vimscript
        "lua_ls",          -- lua
    },
    handlers = {
        function(server_name)
            local server = require('lspconfig')[server_name]
            if server.setup then
                server.setup({})
            end
        end,
    },
})

require("mason-tool-installer").setup({
    ensure_installed = {
        -- DAP
        "bash-debug-adapter",    -- bash
        "codelldb",              -- c/c++/rust
        "debugpy",               -- python
        "haskell-debug-adapter", -- haskell
        "js-debug-adapter",      -- javascript/typescript
        "kotlin-debug-adapter",  -- kotlin

        -- Linters
        "shellcheck",      -- bash/zsh
        "cppcheck",        -- c/c++
        "hadolint",        -- docker
        "eslint_d",        -- javascript/jsx/typescript
        "jsonlint",        -- json
        "ktlint",          -- kotlin
        "checkmake",       -- makefile
        "markdownlint",    -- markdown
        "statix",          -- nix
        "ruff",            -- python
        "sqlfluff",        -- sql
        "luacheck",        -- lua
        "vale",            -- text/markdown prose

        -- Formatters
        "shfmt",           -- bash/zsh
        "clang-format",    -- c/c++/glsl
        "cmake-format",    -- cmake
        "fourmolu",        -- haskell
        "prettier",        -- html/json/jsx/js/ts/markdown/jinja/nunjucks
        "jq",              -- jq/json
        "ktlint",          -- kotlin
        "nixpkgs-fmt",     -- nix
        "ruff",            -- python
        "rustfmt",         -- rust
        "sql-formatter",   -- sql
        "stylua",          -- lua
    },
})
