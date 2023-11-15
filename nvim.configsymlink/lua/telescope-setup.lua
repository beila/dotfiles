-- [[ Configure Telescope ]]
-- See `:help telescope` and `:help telescope.setup()`
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        -- ['<C-u>'] = false,
        -- ['<C-d>'] = false,
        ["<C-Down>"] = require('telescope.actions').cycle_history_next,
        ["<C-Up>"] = require('telescope.actions').cycle_history_prev,
      },
    },
    -- path_display = 'smart',
  },
}

-- Enable telescope fzf native, if installed
pcall(require('telescope').load_extension, 'fzf')

-- Telescope live_grep in git root
-- Function to find the git root directory based on the current buffer's path
local function find_git_root()
  -- Use the current buffer's path as the starting point for the git search
  local current_file = vim.api.nvim_buf_get_name(0)
  local current_dir
  local cwd = vim.fn.getcwd()
  -- If the buffer is not associated with a file, return nil
  if current_file == "" then
    current_dir = cwd
  else
    -- Extract the directory from the current file's path
    current_dir = vim.fn.fnamemodify(current_file, ":h")
  end

  -- Find the Git root directory from the current file's path
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.escape(current_dir, " ") .. " rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then
    print("Not a git repository. Searching on current working directory")
    return cwd
  end
  return git_root
end

-- Custom live_grep function to search in git root
local function live_grep_git_root()
  local git_root = find_git_root()
  if git_root then
    require('telescope.builtin').live_grep({
      search_dirs = {git_root},
    })
  end
end

vim.api.nvim_create_user_command('LiveGrepGitRoot', live_grep_git_root, {})

-- See `:help telescope.builtin`
vim.keymap.set('n', '<leader>b', require('telescope.builtin').oldfiles, { desc = '[ ] Find recently opened files' })
vim.keymap.set('n', '<leader>\'', function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  require('telescope.builtin').current_buffer_fuzzy_find(--[[ require('telescope.themes').get_dropdown {
    winblend = 10,
    previewer = false,
  } ]])
end, { desc = '[/] Fuzzily search in current buffer' })

vim.keymap.set('n', '<leader>f', require('telescope.builtin').git_files, { desc = 'Search Git [F]iles' })
vim.keymap.set('n', '<leader>F', require('telescope.builtin').find_files, { desc = 'Search [F]iles including ignored ones' })
vim.keymap.set('n', '<leader>h', require('telescope.builtin').help_tags, { desc = 'Search [H]elp' })
vim.keymap.set('n', '<leader>H', require('telescope.builtin').man_pages, { desc = 'Manual Pages' })
vim.keymap.set({'n', 'v'}, '<leader>g', require('telescope.builtin').grep_string, { desc = 'Search Current Word' })
vim.keymap.set('n', '<leader>d', require('telescope.builtin').diagnostics, { desc = 'Search [D]iagnostics' })

vim.keymap.set('n', '<leader>s', require('telescope.builtin').git_status, { desc = 'Git [S]tatus' })
vim.keymap.set('n', '<leader>t', require('telescope.builtin').builtin, { desc = '[T]elescope Builtins' })
vim.keymap.set('n', '<leader>q', require('telescope.builtin').quickfix, { desc = '[Q]uickfix' })
vim.keymap.set('n', '<leader>Q', require('telescope.builtin').quickfixhistory, { desc = '[Q]uickfix history' })
vim.keymap.set('n', '<leader>;', require('telescope.builtin').command_history, { desc = 'Command History' })
vim.keymap.set('n', '<leader>/', require('telescope.builtin').search_history, { desc = 'Search History' })
vim.keymap.set('n', '<leader>r', require('telescope.builtin').spell_suggest, { desc = '[R]ecommend spelling for the current word' })
vim.keymap.set('n', '<leader><space>', require('telescope.builtin').jumplist, { desc = 'Jump list' })

vim.keymap.set('n', '<leader>cr', require('telescope.builtin').lsp_references, { desc = '[C]ode [R]eferences' })
vim.keymap.set('n', '<leader>ci', require('telescope.builtin').lsp_incoming_calls, { desc = '[C]ode [I]ncoming calls' })
vim.keymap.set('n', '<leader>co', require('telescope.builtin').lsp_outgoing_calls, { desc = '[C]ode [O]outgoing calls' })
vim.keymap.set('n', '<leader>cd', require('telescope.builtin').lsp_definitions, { desc = '[C]ode [D]efinitions' })
vim.keymap.set('n', '<leader>ct', require('telescope.builtin').lsp_type_definitions, { desc = '[C]ode [T]ype Definitions' })
vim.keymap.set('n', '<leader>cm', require('telescope.builtin').lsp_implementations, { desc = '[C]ode I[m]plementations' })
vim.keymap.set('n', '<leader>cl', require('telescope.builtin').lsp_document_symbols, { desc = '[C]ode [L]ocal symbols' })
vim.keymap.set('n', '<leader>cs', require('telescope.builtin').lsp_workspace_symbols, { desc = '[C]ode Workspace [S]ymbols' })
vim.keymap.set('n', '<leader>cw', require('telescope.builtin').lsp_dynamic_workspace_symbols, { desc = '[C]ode [W]orkspace symbols dynamically' })

vim.keymap.set({'n', 'v'}, '<leader>l', require('telescope.builtin').git_bcommits, { desc = 'Git [L]og for buffer' })
require("telescope").setup {
  pickers = {
    git_bcommits = {
      mappings = {
        i = {
          -- It checks out the current file from the selected commit and drop all the current changes!
          ["<CR>"] = false,
        },
        n = {
          ["<CR>"] = false,
        },
      },
    },
  },
}

-- vim: ts=2 sts=2 sw=2 et
