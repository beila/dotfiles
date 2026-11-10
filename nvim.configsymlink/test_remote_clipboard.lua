local config = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = config .. "/lua/?.lua;" .. package.path
assert(require("remote-clipboard").setup(), "remote provider was not enabled")
assert(vim.o.clipboard == "", "ordinary yanks must remain independent")

local function clipboard()
	local file = assert(io.open(vim.env.TEST_CLIPBOARD, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

vim.fn.setreg("+", "한글\nremote copy")
assert(clipboard() == "한글\nremote copy", "copy changed the bytes")
local file = assert(io.open(vim.env.TEST_CLIPBOARD, "wb"))
file:write("local clipboard\n\n")
file:close()
assert(vim.fn.getreg("+") == "local clipboard\n\n", "paste returned stale content")
vim.fn.setreg("*", "primary selection")
assert(clipboard() == "primary selection", "primary selection missed the bridge")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ordinary yank" })
vim.cmd.normal({ "yy", bang = true })
assert(clipboard() == "primary selection", "ordinary yank changed the clipboard")

require("picker-clipboard").copy("commit-id")
assert(clipboard() == "commit-id", "picker did not reach the local clipboard")

local plugins = vim.env.TEST_NVIM_PLUGINS
assert(vim.fn.isdirectory(plugins .. "/fzf-lua") == 1, "fzf-lua is required")
vim.opt.runtimepath:append(plugins .. "/fzf-lua")
require("picker-clipboard").copy_files({ "\27[31msub/file with spaces.txt\27[0m" }, { cwd = "/repo" })
assert(clipboard() == "sub/file with spaces.txt", "file picker copied a decorated path")

assert(vim.fn.isdirectory(plugins .. "/nvim-tree.lua") == 1, "nvim-tree is required")
vim.opt.runtimepath:append(plugins .. "/nvim-tree.lua")
dofile(config .. "/vimrcs/nvim-tree.lua")
local api = require("nvim-tree.api")
local tree_root = vim.env.XDG_RUNTIME_DIR
local path = tree_root .. "/tree-file.txt"
vim.fn.writefile({ "tree" }, path)
api.tree.open({ path = tree_root })
api.tree.find_file({ buf = path, focus = true })
local mapping = vim.fn.maparg("Y", "n", false, true)
assert(type(mapping.callback) == "function", "nvim-tree Y mapping is missing")
mapping.callback()
assert(clipboard() == "tree-file.txt", "nvim-tree Y did not reach the local clipboard")
print("PASS: remote clipboard provider, picker paths, and nvim-tree Y")
