-- Show diagnostics as virtual lines below the source
vim.diagnostic.config { virtual_lines = false, virtual_text = true }

-- Softer colors for diagnostic virtual text (follows colorscheme)
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function()
    vim.api.nvim_set_hl(0, 'DiagnosticVirtualTextError', { link = 'Comment' })
    vim.api.nvim_set_hl(0, 'DiagnosticVirtualTextWarn', { link = 'Comment' })
    vim.api.nvim_set_hl(0, 'DiagnosticVirtualTextInfo', { link = 'Comment' })
    vim.api.nvim_set_hl(0, 'DiagnosticVirtualTextHint', { link = 'Comment' })
  end,
})

-- LSP keymaps (applied to all servers via LspAttach)

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
        map("n", "<leader>e", vim.diagnostic.open_float)
    end,
})
