local function fail(message)
	error("test_fzf_lsp_symbols: " .. message, 0)
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(script, ":p:h")
package.path = config_root .. "/lua/?.lua;" .. package.path

local setup
local document_opts
package.loaded["fzf-lua"] = {
	defaults = { actions = { files = {} } },
	setup_fzfvim_cmds = function() end,
	lsp_document_symbols = function(opts)
		document_opts = opts
	end,
	lsp_workspace_symbols = function() end,
	setup = function(opts)
		setup = opts
	end,
}
package.loaded["fzf-lua.actions"] = {
	toggle_ignore = function() end,
}
package.loaded["fzf-lua.utils"] = {
	lua_regex_escape = function(text)
		return text
	end,
}
package.loaded["jj-diff-picker"] = {
	revisions = function() end,
	current_file_revisions = function() end,
}
package.loaded["jj-workspace-picker"] = {
	workspaces = function() end,
	bookmarks = function() end,
}

dofile(config_root .. "/vimrcs/fzf.lua")

if not setup or not setup.lsp or not setup.lsp.symbols then
	fail("fzf-lua LSP symbol configuration was not captured")
end
if setup.lsp.symbols.fzf_opts["--no-hscroll"] ~= true then
	fail("selected LSP symbols can still shift horizontally")
end
if setup.lsp.document_symbols.fzf_opts["--tabstop"] ~= "8" then
	fail("document symbol positions do not align before the hierarchy")
end

vim.bo.filetype = "markdown"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"## [x] top-level request with #inline",
	"### clarification",
	"1. Strip #s-1 only when the rendered heading is 개요.",
	"Setext heading",
	"--------------",
})

local mapping
for _, candidate in ipairs(vim.api.nvim_get_keymap("n")) do
	if candidate.lhs == "<F8>" then
		mapping = candidate
		break
	end
end
if not mapping or type(mapping.callback) ~= "function" then
	fail("F8 document-symbol mapping was not captured")
end
mapping.callback()

local filter = document_opts and document_opts.regex_filter
if type(filter) ~= "function" then
	fail("Markdown document symbols do not have a heading filter")
end

local picker_bufnr = vim.api.nvim_create_buf(false, true)
vim.bo[picker_bufnr].filetype = "fzf"
vim.api.nvim_set_current_buf(picker_bufnr)
local function symbol(lnum, col)
	return { lnum = lnum, col = col }
end

if not filter(symbol(1, 1)) then
	fail("ATX heading was filtered")
end
if filter(symbol(1, 32)) then
	fail("inline fragment inside a heading was retained")
end
if not filter(symbol(2, 1)) then
	fail("nested ATX heading was filtered")
end
if filter(symbol(3, 10)) then
	fail("inline fragment was retained as a document symbol")
end
if not filter(symbol(4, 1)) then
	fail("Setext heading was filtered")
end

print("PASS: fzf-lua LSP symbols keep hierarchy and align selected rows")
