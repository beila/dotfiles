-- Inlay hints (neovim >= 0.10) and auto signature help (lsp_signature.nvim)

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('lsp_enhancements', { clear = true }),
  callback = function(ev)
    if vim.lsp.inlay_hint then vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf }) end
    require('lsp_signature').on_attach({}, ev.buf)
  end,
})
