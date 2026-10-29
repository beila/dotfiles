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

if not setup or not setup.lsp or not setup.lsp.symbols then
	fail("fzf-lua LSP symbol configuration was not captured")
end
if setup.lsp.symbols.child_prefix ~= false then
	fail("nested LSP symbols are still indented")
end

print("PASS: fzf-lua LSP symbol columns stay aligned")
