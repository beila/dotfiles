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

local function yank(keys, lines, cursor)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or source_lines)
	vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
	test_clipboard["+"] = ""
	vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
	return test_clipboard["+"]
end

local function assert_same_yank(label, native_keys, mapped_keys, lines, cursor)
	local expected_value = yank(native_keys, lines, cursor)
	local actual_value = yank(mapped_keys, lines, cursor)
	if actual_value ~= expected_value then
		fail(label .. " copied " .. vim.inspect(actual_value) .. ", expected " .. vim.inspect(expected_value))
	end
end

local expected = yank([["+2yap]])
local actual = yank([[2 yap]])

if actual ~= expected then
	fail("leading count copied " .. vim.inspect(actual) .. ", expected " .. vim.inspect(expected))
end

if not actual:find("second paragraph", 1, true) or actual:find("third paragraph", 1, true) then
	fail("leading count did not copy exactly two paragraphs: " .. vim.inspect(actual))
end

actual = yank([[ 2yap]])

if actual ~= expected then
	fail("count after leader copied " .. vim.inspect(actual) .. ", expected " .. vim.inspect(expected))
end

assert_same_yank("paragraph text object", [["+3yip]], [[ 3yip]])
assert_same_yank("sentence text object", [["+2yas]], [[ 2yas]], { "First sentence. Second sentence. Third sentence." })
assert_same_yank("parenthesis text object", [["+2yi(]], [[ 2yi(]], { "before (outer (inner) tail) after" }, { 1, 15 })

local many_paragraphs = {}
for number = 1, 13 do
	table.insert(many_paragraphs, "paragraph " .. number)
	table.insert(many_paragraphs, "")
end
assert_same_yank("multi-digit count", [["+12yip]], [[ 12yip]], many_paragraphs)

expected = yank([["+yap]])
actual = yank([[ yap]])

if actual ~= expected then
	fail("uncounted yank copied " .. vim.inspect(actual) .. ", expected " .. vim.inspect(expected))
end

print("PASS: counted clipboard yank")
