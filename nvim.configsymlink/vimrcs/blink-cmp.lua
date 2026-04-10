require('blink.cmp').setup {
  keymap = {
    preset = 'default',
    ['<CR>'] = { 'accept', 'fallback' },
    ['<Tab>'] = { 'select_next', 'fallback' },
    ['<S-Tab>'] = { 'select_prev', 'fallback' },
  },
  sources = {
    default = { 'lsp', 'path' },
  },
  signature = { enabled = true },
}
