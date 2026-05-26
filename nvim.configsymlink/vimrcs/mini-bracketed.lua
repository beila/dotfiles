-- Only `[y`/`]y` enabled (cycle through yank history after a paste).
-- All other targets disabled — bracket-key bloat we don't want.
require('mini.bracketed').setup {
  buffer     = { suffix = '' },
  comment    = { suffix = '' },
  conflict   = { suffix = '' },
  diagnostic = { suffix = '' },
  file       = { suffix = '' },
  indent     = { suffix = '' },
  jump       = { suffix = '' },
  location   = { suffix = '' },
  oldfile    = { suffix = '' },
  quickfix   = { suffix = '' },
  treesitter = { suffix = '' },
  undo       = { suffix = '' },
  window     = { suffix = '' },
}
