local function fail(message)
	error("test_counted_clipboard_yank: " .. message, 0)
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(script, ":p:h")
local test_clipboard = dofile(config_root .. "/test_clipboard.lua")
package.path = config_root .. "/lua/?.lua;" .. package.path

vim.g.mapleader = "'"
vim.cmd("map <Space> <Leader>")
require("clipboard-yank").setup()

local source_lines = {
	"first paragraph",
	"",
	"second paragraph",
	"",
	"third paragraph",
}

local function yank(keys)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, source_lines)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	test_clipboard["+"] = ""
	vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
	return test_clipboard["+"]
end

local expected = yank([["+2yap]])
local actual = yank([[2 yap]])

if actual ~= expected then
	fail("leading count copied " .. vim.inspect(actual) .. ", expected " .. vim.inspect(expected))
end

if not actual:find("second paragraph", 1, true) or actual:find("third paragraph", 1, true) then
	fail("leading count did not copy exactly two paragraphs: " .. vim.inspect(actual))
end

expected = yank([["+yap]])
actual = yank([[ yap]])

if actual ~= expected then
	fail("uncounted yank copied " .. vim.inspect(actual) .. ", expected " .. vim.inspect(expected))
end

print("PASS: counted clipboard yank")
