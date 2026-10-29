local function fail(message)
	error("test_fzf_lsp_symbols: " .. message, 0)
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(script, ":p:h")
package.path = config_root .. "/lua/?.lua;" .. package.path

local setup
package.loaded["fzf-lua"] = {
	defaults = { actions = { files = {} } },
	setup_fzfvim_cmds = function() end,
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

if not setup or not setup.lsp or not setup.lsp.symbols or not setup.lsp.document_symbols then
	fail("fzf-lua LSP symbol configuration was not captured")
end
if setup.lsp.symbols.fzf_opts["--no-hscroll"] ~= true then
	fail("selected LSP symbols can still shift horizontally")
end

local filter = setup.lsp.document_symbols.regex_filter
if type(filter) ~= "function" then
	fail("Markdown document symbols do not have a heading filter")
end

vim.bo.filetype = "markdown"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"## [x] top-level request with #inline",
	"### clarification",
	"1. Strip #s-1 only when the rendered heading is 개요.",
	"Setext heading",
	"--------------",
})

local ctx = { bufnr = 0 }
if not filter({ lnum = 1, col = 1 }, ctx) then
	fail("ATX heading was filtered")
end
if filter({ lnum = 1, col = 32 }, ctx) then
	fail("inline fragment inside a heading was retained")
end
if not filter({ lnum = 2, col = 1 }, ctx) then
	fail("nested ATX heading was filtered")
end
if filter({ lnum = 3, col = 10 }, ctx) then
	fail("inline fragment was retained as a document symbol")
end
if not filter({ lnum = 4, col = 1 }, ctx) then
	fail("Setext heading was filtered")
end

vim.bo.filetype = "lua"
if not filter({ lnum = 3, col = 10 }, ctx) then
	fail("non-Markdown symbols were filtered")
end

print("PASS: fzf-lua LSP symbols keep hierarchy and align selected rows")
