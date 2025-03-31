-- https://w.amazon.com/bin/view/Users/Ethdestr/vim/#HNeovimLocalConfiguration

-- Only load when not in vscode
if vim.g.vscode then
  return
end

-- [[ Barium support ]]
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- https://w.amazon.com/bin/view/Barium/#HVimandNeovim
-- Remove hyphen because it breaks vim/neovim
vim.filetype.add({ filename = { Config = "brazilconfig" } })

-- Check if the config is already defined (useful when reloading this file)
if not configs.barium then
  configs.barium = {
    default_config = {
      cmd = { 'barium' },
      filetypes = { 'brazilconfig' },
      root_dir = function(fname)
        return lspconfig.util.find_git_ancestor(fname)
      end,
      settings = {},
    },
  }
end

lspconfig.barium.setup({})

-- [[ Add support for Bemol folders ]]
-- https://w.amazon.com/bin/view/Bemol/#HnvimbuiltinLSP28withlsp-configand2Forlsp-zero29
local function bemol()
  -- Find bemol directory based on current working directory, not parent directory of current buffer.
  local bemol_dir = vim.fs.find({ '.bemol' }, { upward = true, type = 'directory' })[1]
  local ws_folders_lsp = {}
  if not bemol_dir then
    vim.notify(".bemol directory not found! Not in a Brazil workspace?", vim.log.levels.WARN)
  else
    vim.notify(".bemol directory found: " .. bemol_dir, vim.log.levels.INFO)
    local file = io.open(bemol_dir .. '/ws_root_folders', 'r')
    if file then
      for line in file:lines() do
        table.insert(ws_folders_lsp, line)
      end
      file:close()
    end
  end

  for _, line in ipairs(ws_folders_lsp) do
    vim.lsp.buf.add_workspace_folder(line)
  end

  return ws_folders_lsp
end

-- Should be rarely needed because of auto command defined below
vim.api.nvim_create_user_command(
  'BemolAdditions',
  bemol,
  {
    desc = 'Add bemol detected workspace folders',
  }
)

vim.api.nvim_create_autocmd('LspAttach',
  {
    -- Should stack with existing autogroup for defining keymaps, etc.
    group = vim.api.nvim_create_augroup('UserLspConfig', { clear = false }),

    -- bemol supports multiple workspace roots for Java, Python, and Ruby Brazil workspaces.
    -- https://w.amazon.com/bin/view/Bemol/#HBrazilPlugins
    pattern = { '*.java', '*.py', '*.rb' },

    callback = function(args)
      bemol()
    end,
  }
)
