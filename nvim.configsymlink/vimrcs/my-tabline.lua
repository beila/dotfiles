-- Custom tabline: <tabnr> <path> per tab.
-- Replaces nvim's default which prepends a window-count digit per tab — useless
-- in a fzf-driven workflow with many tabs.
--
-- Path format:
--   - Strip $HOME/ prefix (so ~/dev/foo/bar.cpp → dev/foo/bar.cpp)
--   - When the per-tab budget is tight, prefer leading dirs and the file
--     extension; elide the middle with '…'
-- Tab number gets its own highlight group `MyTabNum` (bold + reverse) so it
-- stands out regardless of color scheme.

local function modified(bufnr)
  return vim.bo[bufnr].modified and '+' or ''
end

-- Display path: strip $HOME/, fall back to ':~' if outside home, [special]
-- markers for non-file buffers.
local function tab_path(tabnr)
  local winid = vim.api.nvim_tabpage_get_win(tabnr)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    local bt = vim.bo[bufnr].buftype
    if bt == 'terminal' then return '[term]' end
    if bt == 'quickfix' then return '[qf]' end
    if bt == 'help'     then return '[help]' end
    return '[No Name]'
  end
  -- ':~:.' first tries cwd-relative; if the file isn't under cwd it falls
  -- back to home-relative ('~/...'). We then strip the leading '~/' so all
  -- on-tab paths look uniform without the tilde noise.
  local p = vim.fn.fnamemodify(name, ':~:.')
  return (p:gsub('^~/', ''))
end

-- Truncate `s` to `budget` cells, prioritising leading directories and the
-- file extension. Elide the middle with '…'. budget < 4 → fall back to
-- whatever fits + '…'.
local function shrink(s, budget)
  if vim.fn.strdisplaywidth(s) <= budget then return s end
  if budget < 4 then
    return vim.fn.strcharpart(s, 0, math.max(0, budget - 1)) .. '…'
  end
  -- Carve out '…' + tail (filename + extension); rest is head.
  local tail = s:match('([^/]+)$') or s
  -- Reserve at most half the budget for the tail, but always keep extension.
  local ext = tail:match('%.[^.]+$') or ''
  local tail_budget = math.min(#tail, math.floor(budget / 2))
  if tail_budget < #ext + 2 then tail_budget = math.min(#tail, #ext + 2) end
  local tail_kept
  if #tail <= tail_budget then
    tail_kept = tail
  else
    -- Keep ext, fill remaining with the start of the basename
    local stem_budget = tail_budget - #ext - 1  -- 1 for '…'
    if stem_budget < 1 then
      tail_kept = '…' .. ext
    else
      tail_kept = tail:sub(1, stem_budget) .. '…' .. ext
    end
  end
  local head_budget = budget - vim.fn.strdisplaywidth(tail_kept) - 1  -- 1 for '…'
  if head_budget < 1 then
    return '…' .. tail_kept
  end
  -- s without the tail
  local head = s:sub(1, #s - #tail - 1)  -- drop trailing '/' too
  if vim.fn.strdisplaywidth(head) <= head_budget then
    return head .. '/' .. tail_kept
  end
  return vim.fn.strcharpart(head, 0, head_budget) .. '…/' .. tail_kept
end

function _G.MyTabLine()
  local tabs = vim.api.nvim_list_tabpages()
  local n = #tabs
  if n == 0 then return '' end

  -- Budget: total columns, minus per-tab fixed overhead (number + spaces +
  -- modified marker = ~6), divided across tabs.
  local cols = vim.o.columns
  local overhead = 6
  local per_tab = math.max(8, math.floor(cols / n) - overhead)

  local s = {}
  local current = vim.api.nvim_get_current_tabpage()
  for i, tabnr in ipairs(tabs) do
    local active = (tabnr == current)
    local body_hl = active and '%#TabLineSel#' or '%#TabLine#'
    local num_hl  = '%#MyTabNum#'
    local winid = vim.api.nvim_tabpage_get_win(tabnr)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local path  = shrink(tab_path(tabnr), per_tab)
    local mod   = modified(bufnr)
    table.insert(s, table.concat({
      body_hl, '%', i, 'T',
      num_hl, ' ', tostring(i), ' ',
      body_hl, ' ', path, mod, ' ',
    }))
  end
  table.insert(s, '%#TabLineFill#%T')
  return table.concat(s)
end

-- Bold + reverse-video tab number, color-scheme independent.
local function set_hl()
  vim.api.nvim_set_hl(0, 'MyTabNum', { bold = true, reverse = true })
end
set_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_hl })

vim.opt.tabline = '%!v:lua.MyTabLine()'
vim.opt.showtabline = 1  -- show only when ≥2 tabs (default); set to 2 to always show
