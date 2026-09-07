local function fail(message)
	error("test_jj_workspace_picker: " .. message, 0)
end

local function assert_contains(text, expected, label)
	if not text:find(expected, 1, true) then
		fail(label .. ": missing " .. vim.inspect(expected))
	end
end

local function assert_eq(actual, expected, label)
	if actual ~= expected then
		fail(label .. ": expected " .. vim.inspect(expected) .. " got " .. vim.inspect(actual))
	end
end

local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
local repo = base .. "/main"
vim.fn.mkdir(repo, "p")

local git_env = vim.tbl_extend("force", vim.fn.environ(), {
	GIT_AUTHOR_NAME = "JJ Workspace Test",
	GIT_AUTHOR_EMAIL = "jj-workspace@example.com",
	GIT_COMMITTER_NAME = "JJ Workspace Test",
	GIT_COMMITTER_EMAIL = "jj-workspace@example.com",
})

local function run(args, opts)
	opts = opts or {}
	local result = vim.system(args, {
		cwd = opts.cwd or repo,
		env = opts.env,
		text = true,
	}):wait()
	if result.code ~= 0 then
		fail(table.concat(args, " ") .. " failed:\n" .. (result.stderr or ""))
	end
	return vim.trim(result.stdout or "")
end

local function git(args)
	local command = { "git" }
	vim.list_extend(command, args)
	return run(command, { env = git_env })
end

git({ "init", "-q" })
vim.fn.writefile({ "shared file, default workspace" }, repo .. "/sample.txt")
git({ "add", "sample.txt" })
git({ "commit", "-q", "-m", "introduce sample" })

run({ "jj", "git", "init", "--colocate", "." })

-- A second workspace with its own copy of the file, distinguishable by content.
local feature = base .. "/feature"
run({ "jj", "workspace", "add", feature })
vim.fn.writefile({ "shared file, feature workspace" }, feature .. "/sample.txt")

local captured
package.loaded["fzf-lua"] = {
	fzf_exec = function(contents, opts)
		captured = { contents = contents, opts = opts }
	end,
}
package.loaded["fzf-lua.utils"] = {
	strip_ansi_coloring = function(text)
		return (text:gsub("\27%[[0-9;]*m", ""))
	end,
}

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fs.dirname(script)
package.path = config_root .. "/lua/?.lua;" .. package.path

-- Launch from the default workspace's file.
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
require("jj-workspace-picker").workspaces()

if not captured then
	fail("picker did not open")
end
assert_contains(captured.opts.prompt, "jj workspaces", "prompt")
assert_contains(captured.opts.fzf_opts["--header"], "switch tab", "header")

-- The list command lists both workspaces with their roots in field 2.
local rows = run({ "sh", "-c", captured.contents })
local feature_row, default_row
for row in rows:gmatch("[^\n]+") do
	local fields = vim.split(package.loaded["fzf-lua.utils"].strip_ansi_coloring(row), "\t", { plain = true })
	if fields[1] == "feature" then
		feature_row = row
	elseif fields[1] == "default" then
		default_row = row
	end
end
if not feature_row or not default_row then
	fail("workspace rows missing from list output:\n" .. rows)
end

-- The preview for the feature row runs `jj -R <feature root> log` and succeeds.
local preview_command = captured.opts.preview:gsub("{}", vim.fn.shellescape(feature_row))
local preview = run({ "sh", "-c", preview_command })
if preview == "" then
	fail("feature workspace preview was empty")
end

-- Selecting the feature workspace switches the current window to the feature
-- copy of the same relative file.
captured.opts.actions.enter({ feature_row })

local switched = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
assert_eq(vim.fs.normalize(switched), vim.fs.normalize(feature .. "/sample.txt"), "switched buffer path")

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert_eq(lines[1], "shared file, feature workspace", "switched buffer content")

-- ctrl-b toggles from the workspace picker to the bookmark picker; scheduled,
-- so drain the scheduler before inspecting the re-dispatched picker.
git({ "-c", "user.email=t@t", "-c", "user.name=t", "branch", "-f", "wip", "HEAD" })
run({ "jj", "--ignore-working-copy", "bookmark", "track", "wip@git" })
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
require("jj-workspace-picker").workspaces()
local workspace_capture = captured
workspace_capture.opts.actions["ctrl-b"]()
vim.wait(200, function()
	return captured ~= workspace_capture
end)
if captured == workspace_capture then
	fail("ctrl-b did not re-dispatch to the bookmark picker")
end
assert_contains(captured.opts.prompt, "jj bookmarks", "toggled prompt")

-- ctrl-b from the bookmark picker toggles back to workspaces.
local bookmark_capture = captured
bookmark_capture.opts.actions["ctrl-b"]()
vim.wait(200, function()
	return captured ~= bookmark_capture
end)
assert_contains(captured.opts.prompt, "jj workspaces", "toggled-back prompt")

vim.fn.delete(base, "rf")
print("PASS: jj workspace picker switch")
