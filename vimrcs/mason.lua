-- mason.setup() is in lsp-zero.lua (loads first alphabetically)
--
-- Coverage table (LSPs in lsp-zero.lua, rest here):
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
