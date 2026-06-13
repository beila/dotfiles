-- Project autoformat on autosave (CursorHold/BufLeave/FocusLost)
-- .nvim.lua sets vim.b.autoformat_fts per project (loaded by myvimrc)
-- .nvim.lua creates buffer-local BufWritePre for explicit :w

vim.api.nvim_create_autocmd({ 'CursorHold', 'BufLeave', 'FocusLost' }, {
  group = vim.api.nvim_create_augroup('project_autoformat', { clear = true }),
  callback = function()
    local fts = vim.b.autoformat_fts
    if fts and fts[vim.bo.filetype] and vim.bo.buftype == '' and vim.bo.modified then
      vim.cmd('silent! undojoin') -- merge format into previous edit for single undo
      local ok, err = pcall(vim.lsp.buf.format, { async = false })
      if not ok then vim.notify('autoformat: ' .. err, vim.log.levels.WARN) end
    end
  end,
})
