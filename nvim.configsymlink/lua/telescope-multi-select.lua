-- https://github.com/nvim-telescope/telescope.nvim/issues/1048#issuecomment-1679797700

local select_one_or_multi = function(prompt_bufnr)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local multi = picker:get_multi_selection()
  if not vim.tbl_isempty(multi) then
    require("telescope.actions").send_selected_to_qflist(prompt_bufnr) vim.cmd.cfdo("edit")
  else
    require('telescope.actions').select_default(prompt_bufnr)
  end
end

require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ["<CR>"] = select_one_or_multi,
      },
      n = {
        ["<CR>"] = select_one_or_multi,
      }
    }
  }
}
