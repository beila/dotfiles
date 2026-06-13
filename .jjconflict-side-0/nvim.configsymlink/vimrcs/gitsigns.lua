-- gitsigns.nvim — git gutter signs with jj support
-- Diffs against jj's @- parent instead of git HEAD

local gs = require('gitsigns')

gs.setup {
  signs = {
    add          = { text = '+' },
    change       = { text = '~' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
  },
  sign_priority = 6,
  update_debounce = 250,
  on_attach = function(bufnr)
    local map = function(mode, lhs, rhs)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr })
    end
    map('n', ']c', gs.next_hunk)
    map('n', '[c', gs.prev_hunk)
    map('n', '<leader>hp', gs.preview_hunk)
    map('n', '<leader>hr', gs.reset_hunk)
    map('n', '<leader>hb', function() gs.blame_line { full = true } end)
  end,
}

-- Set diff base to jj's @- (parent of working copy) if in a jj repo
local function update_jj_base()
  local obj = vim.system({ 'jj', 'log', '-r', '@-', '-T', 'commit_id', '--no-graph' }, { text = true }):wait()
  if obj.code == 0 and obj.stdout ~= '' then
    gs.change_base(vim.trim(obj.stdout), true)
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
  group = vim.api.nvim_create_augroup('gitsigns_jj_base', { clear = true }),
  callback = function() vim.schedule(update_jj_base) end,
})
