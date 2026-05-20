-- Custom tabline: <tabnr> <filename> per tab.
-- Replaces nvim's default which prepends a window-count digit when a tab
-- has >1 window — useless noise in a fzf-driven workflow with many tabs.
--
-- Format per tab: " 1 foo.txt + " (number, name, modified marker)
-- Highlight: TabLineSel for active tab, TabLine for others.

local function modified(bufnr)
  return vim.bo[bufnr].modified and ' +' or ''
end

local function tab_filename(tabnr)
  local winid = vim.api.nvim_tabpage_get_win(tabnr)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    local bt = vim.bo[bufnr].buftype
    if bt == 'terminal' then return '[term]' end
    if bt == 'quickfix' then return '[qf]' end
    if bt == 'help' then return '[help]' end
    return '[No Name]'
  end
  return vim.fn.fnamemodify(name, ':t')
end

function _G.MyTabLine()
  local s = {}
  local current = vim.api.nvim_get_current_tabpage()
  for i, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
    local hl = (tabnr == current) and '%#TabLineSel#' or '%#TabLine#'
    local winid = vim.api.nvim_tabpage_get_win(tabnr)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    table.insert(s, hl .. '%' .. i .. 'T ' .. i .. ' ' .. tab_filename(tabnr) .. modified(bufnr) .. ' ')
  end
  table.insert(s, '%#TabLineFill#%T')
  return table.concat(s)
end

vim.opt.tabline = '%!v:lua.MyTabLine()'
vim.opt.showtabline = 1  -- show only when ≥2 tabs (default); set to 2 to always show
