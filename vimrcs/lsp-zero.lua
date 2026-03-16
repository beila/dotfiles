-- Mason must be set up before mason-lspconfig and mason-tool-installer.
-- mason.lua (loaded after this file alphabetically) depends on this.
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

require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
})

vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
        local buf = ev.buf
        local map = function(mode, lhs, rhs)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf })
        end

        -- Navigation
        map("n", "gd", vim.lsp.buf.definition)
        map("n", "gD", vim.lsp.buf.declaration)
        map("n", "gi", vim.lsp.buf.implementation)
        map("n", "go", vim.lsp.buf.type_definition)
        map("n", "gr", vim.lsp.buf.references)
        map("n", "gs", vim.lsp.buf.signature_help)
        map("n", "K", vim.lsp.buf.hover)
        map("n", "<F2>", vim.lsp.buf.rename)

        -- Diagnostics (severity-aware)
        local function goto_diag(dir)
            return function()
                local sev = vim.diagnostic.severity
                local has = function(s) return next(vim.diagnostic.get(0, { severity = s })) ~= nil end
                local o = has(sev.ERROR) and { severity = sev.ERROR }
                    or has(sev.WARN) and { severity = sev.WARN }
                    or has(sev.INFO) and { severity = sev.INFO }
                    or { severity = sev.HINT }
                vim.diagnostic[dir](o)
            end
        end
        map("n", "]d", goto_diag("goto_next"))
        map("n", "[d", goto_diag("goto_prev"))
        map({ "n", "v" }, "}D", function() vim.diagnostic.goto_next() end)
        map({ "n", "v" }, "{D", function() vim.diagnostic.goto_prev() end)

        -- Actions
        map({ "n", "v" }, "<leader>aa", function() require("fzf-lua").lsp_code_actions() end)
        map({ "n", "v" }, "<leader>af", function() vim.lsp.buf.format() end)
    end,
})
