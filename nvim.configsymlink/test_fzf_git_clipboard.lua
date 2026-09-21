local function fail(message)
	error("test_fzf_git_clipboard: " .. message, 0)
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(script, ":p:h")
local test_clipboard = dofile(config_root .. "/test_clipboard.lua")
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

if not setup or not setup.git then
	fail("fzf-lua Git configuration was not captured")
end

for _, provider in ipairs({ "commits", "bcommits", "blame", "reflog" }) do
	local action = setup.git[provider].actions["ctrl-y"]
	if not action or type(action.fn) ~= "function" or not action.exec_silent then
		fail(provider .. " does not define the Ctrl-Y clipboard action")
	end

	for _, register in ipairs({ "+", '"', "0" }) do
		vim.fn.setreg(register, "")
	end
	action.fn({ "\27[33mabc1234\27[0m commit subject" }, {})
	if test_clipboard["+"] ~= "abc1234" then
		fail(provider .. " Ctrl-Y did not copy to the system clipboard")
	end
	for _, register in ipairs({ '"', "0" }) do
		if vim.fn.getreg(register) ~= "abc1234" then
			fail(provider .. " Ctrl-Y did not copy to register " .. register)
		end
	end
end

local action = setup.git.bcommits.actions["ctrl-y"]
action.fn({ "display text" }, {
	fn_match_commit_hash = function()
		return "def5678"
	end,
})
if test_clipboard["+"] ~= "def5678" then
	fail("Ctrl-Y ignored the provider-specific commit matcher")
end

print("PASS: fzf-lua Git clipboard actions")
