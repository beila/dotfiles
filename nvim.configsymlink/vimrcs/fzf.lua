local fzf_lua = require("fzf-lua")

fzf_lua.setup_fzfvim_cmds()

local script_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')

-- <leader>f: jj/git tracked files, <leader>F: all files (set in fzf.vimrc)
vim.keymap.set({ "n", "v", "i" }, "<leader>f",
    function()
        local root = vim.system({ 'jj', 'root' }, { text = true }):wait()
        if root.code == 0 then
            local cmd_jj = 'jj file list'
            local cmd_all = script_dir .. '/jj-file-list-all'
            local jj_cwd = vim.trim(root.stdout)
            local show_sub = false
            local function make_opts(query)
                local opts = {
                    prompt = show_sub and 'jj+sub files> ' or 'jj files> ',
                    cwd = jj_cwd,
                    query = query,
                    preview = 'bat --style=numbers --color=always -- {1} 2>/dev/null || ls -1A --color=always {1}',
                    fzf_opts = {
                        ['--header'] = 'ctrl-g: toggle submodules | '
                            .. (show_sub and 'submodules: ON' or 'submodules: OFF'),
                    },
                }
                opts.actions = vim.tbl_extend('force', fzf_lua.defaults.actions.files, {
                    ['ctrl-g'] = { fn = function(_, opts)
                        show_sub = not show_sub
                        local q = opts.last_query
                        fzf_lua.fzf_exec(show_sub and cmd_all or cmd_jj, make_opts(q))
                    end, exec_silent = true },
                })
                return opts
            end
            fzf_lua.fzf_exec(cmd_jj, make_opts())
        else
            fzf_lua.git_files()
        end
    end,
    {})

-- All files including gitignored
vim.keymap.set({ "n", "v", "i" }, "<leader>F",
    function() fzf_lua.files({ cmd = 'fd --type f --hidden --no-ignore' }) end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<leader>z",
    function() fzf_lua.builtin() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-f>",
    function()
        -- jj-first, git-fallback
        local root = vim.system({ 'jj', 'root' }, { text = true }):wait()
        if root.code == 0 then
            fzf_lua.fzf_exec('jj --quiet diff --name-only', {
                prompt = 'jj changed> ',
                cwd = vim.trim(root.stdout),
                previewer = false,
                preview = 'jj --quiet diff --color=always -- {1}',
                actions = fzf_lua.defaults.actions.files,
            })
        else
            fzf_lua.git_status()
        end
    end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-b>",
    function() fzf_lua.git_branches() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-t>",
    function() fzf_lua.git_tags() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-h>",
    function() fzf_lua.git_commits() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-s>",
    function() fzf_lua.git_stash() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g><C-d>",
    function()
        vim.cmd "Git! difftool"
        vim.cmd "cclose"
        fzf_lua.quickfix()
    end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-g>d",
    function()
        vim.cmd "Git! difftool --name-only --merge-base @{u}"
        vim.cmd "cclose"
        fzf_lua.quickfix()
    end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<leader><tab>",
    function() fzf_lua.tabs() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<F8>",
    function() fzf_lua.lsp_document_symbols() end,
    {})

vim.keymap.set({ "n", "v", "i" }, "<C-]>",
    function() fzf_lua.lsp_finder() end,
    {})

vim.keymap.set({ "n", "v" }, "<leader> ",
    function() fzf_lua.resume() end,
    {})

local actions = require "fzf-lua.actions"
fzf_lua.setup({
    keymap = {
        --[[
           [builtin = {
           [    --[1] = true,
           [    ["<C-n>"] = "preview-page-down",
           [    ["<C-p>"] = "preview-page-up"
           [},
           ]]
        fzf = {
            --[1] = true,
            ["ctrl-a"] = "select-all",
            ["ctrl-n"] = "preview-half-page-down",
            ["ctrl-p"] = "preview-half-page-up",
        }
    },
    fzf_opts = { ['--layout'] = 'reverse-list' },
    defaults = { file_icons = false },
    grep = {
        rg_opts = '--follow --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e',
        rg_glob = true,
        -- first returned string is the new search query
        -- second returned string are (optional) additional rg flags
        -- @return string, string?
        rg_glob_fn = function(query)
            local regex, flags = query:match("^(.-)%s%-%-(.*)$")
            -- If no separator is detected will return the original query
            return (regex or query), flags
        end,
        actions = {
            ["ctrl-r"] = { actions.toggle_ignore },
            ["ctrl-w"] = { function(_, opts) actions.toggle_flag(_, vim.tbl_extend("force", opts, { toggle_flag = '--word-regexp' })) end },
        }
    },
    previewers = {
        git_diff = {
            cmd_modified =
            "DFT_WIDTH=$COLUMNS DFT_COLOR=always git diff {file}; \
             DFT_WIDTH=$COLUMNS DFT_COLOR=always git diff --staged {file}",
        }
    },
    oldfiles = { include_current_session = true },
    lsp = {
        git_icons = true,
        finder = { actions = { ["ctrl-]"] = { function() fzf_lua.lsp_definitions() end } } },
    },
})
