require('blink.cmp').setup {
  keymap = {
    preset = 'default',
    ['<CR>'] = { 'accept', 'fallback' },
    ['<Tab>'] = { 'select_next', 'fallback' },
    ['<S-Tab>'] = { 'select_prev', 'fallback' },
  },
  sources = {
    default = { 'lsp', 'path', 'buffer' },
    providers = {
      -- Rank buffer-word matches above LSP. Default score_offset for
      -- buffer is negative (blink puts it below other sources);
      -- overriding to 100 flips the ordering.
      buffer = { score_offset = 100 },
    },
  },
  signature = { enabled = true },
}
