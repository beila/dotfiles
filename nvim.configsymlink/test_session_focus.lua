local function fail(message)
	error("test_session_focus: " .. message, 0)
end

local function assert_eq(actual, expected, label)
	if actual ~= expected then
		fail(label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
	end
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(script, ":p:h")
package.path = config_root .. "/lua/?.lua;" .. package.path

local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
local session_file = base .. "/session.vim"
local focus_file = base .. "/session-focus.json"

local files = {}
for number = 1, 4 do
	local path = base .. "/file" .. number .. ".txt"
	vim.fn.writefile({ "file " .. number }, path)
	table.insert(files, path)
end

vim.cmd.edit(vim.fn.fnameescape(files[1]))
vim.cmd.vsplit(vim.fn.fnameescape(files[2]))
vim.cmd.tabnew(vim.fn.fnameescape(files[3]))
vim.cmd.vsplit(vim.fn.fnameescape(files[4]))
vim.cmd("2wincmd w")

local expected_buffer = vim.api.nvim_buf_get_name(0)
require("session-focus").save(session_file, focus_file)

vim.cmd("tabonly!")
vim.cmd("only!")
vim.cmd("%bwipeout!")

require("session-focus").restore(session_file, focus_file)
if vim.v.vim_did_enter == 0 then
	vim.api.nvim_exec_autocmds("VimEnter", {})
	vim.wait(1000, function()
		return vim.fn.tabpagenr() == 2 and vim.fn.winnr() == 2
	end)
end

assert_eq(vim.fn.tabpagenr("$"), 2, "tab count")
assert_eq(vim.fn.tabpagenr(), 2, "focused tab")
assert_eq(vim.fn.winnr(), 2, "focused window")
assert_eq(vim.api.nvim_buf_get_name(0), expected_buffer, "focused buffer")

vim.fn.delete(base, "rf")
print("PASS: session tab and window focus")
