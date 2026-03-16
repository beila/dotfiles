-- Mason: LSP servers, DAPs, linters, formatters (all in one place)
--
-- Coverage:
-- Language        LSP                        DAP                    Linter        Formatter
-- awk             awk_ls                     —                      —             —
-- bash/zsh        bashls                     bash-debug-adapter     shellcheck    shfmt
-- c/c++           clangd                     codelldb               cppcheck      clang-format
-- cmake           cmake                      —                      —             cmake-format
-- docker          dockerls + compose         —                      hadolint      —
-- glsl/opengl     glsl_analyzer              —                      —             clang-format
-- haskell         hls                        haskell-debug-adapter  —             fourmolu
-- html/jinja      html                       —                      —             prettier
-- json            jsonls                     —                      jsonlint      prettier
-- js/jsx/ts       ts_ls                      js-debug-adapter       eslint_d      prettier
-- jq              jqls                       —                      —             jq
-- just            —                          —                      —             —
-- kotlin          kotlin_language_server     kotlin-debug-adapter   ktlint        ktlint
-- makefile        —                          —                      checkmake     —
-- markdown        marksman                   —                      markdownlint  prettier
-- nim             nimls                      —                      —             —
-- nix             nil_ls                     —                      statix        nixpkgs-fmt
-- python          pyright                    debugpy                ruff          ruff
-- rust            rust_analyzer              codelldb               —             rustfmt
-- sql             sqlls                      —                      sqlfluff      sql-formatter
-- toml            taplo                      —                      —             (taplo LSP)
-- text            —                          —                      vale          —
-- vimscript       vimls                      —                      —             —
-- lua             lua_ls                     —                      luacheck      stylua
-- systemd         —                          —                      —             —

require('mason').setup({})

require('mason-lspconfig').setup({
    ensure_installed = {
        "awk_ls",          -- awk
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
