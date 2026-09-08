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
vim.fn.writefile({ "second file, default workspace" }, repo .. "/sample2.txt")
git({ "add", "sample.txt", "sample2.txt" })
git({ "commit", "-q", "-m", "introduce sample" })

run({ "jj", "git", "init", "--colocate", "." })

-- A second workspace with its own copies of the files, distinguishable by
-- content, so a two-window switch can be verified per window.
local feature = base .. "/feature"
run({ "jj", "workspace", "add", feature })
vim.fn.writefile({ "shared file, feature workspace" }, feature .. "/sample.txt")
vim.fn.writefile({ "second file, feature workspace" }, feature .. "/sample2.txt")

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
local config_root = vim.fn.fnamemodify(script, ":p:h")
package.path = config_root .. "/lua/?.lua;" .. package.path
-- Load the module under test from THIS checkout, not any installed copy that
-- Neovim's runtime package.path might otherwise resolve first.
package.loaded["jj-workspace-picker"] = dofile(config_root .. "/lua/jj-workspace-picker.lua")

-- Launch from the default workspace's file.
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
require("jj-workspace-picker").workspaces()

if not captured then
	fail("picker did not open")
end
assert_contains(captured.opts.prompt, "jj workspaces", "prompt")
assert_contains(captured.opts.fzf_opts["--header"], "switch tab", "header")

-- The list command lists both workspaces with their roots in field 2; field 1
-- carries a 🟢 marker on the current (launcher) workspace and indents the rest.
local rows = run({ "sh", "-c", captured.contents })
local feature_row, default_row
local function field1_name(row)
	local f1 = vim.split(package.loaded["fzf-lua.utils"].strip_ansi_coloring(row), "\t", { plain = true })[1]
	-- Strip the trailing marker (" 🟢") if present; names stay left-aligned.
	return (f1:gsub("%s*🟢%s*$", ""))
end
for row in rows:gmatch("[^\n]+") do
	local name = field1_name(row)
	if name == "feature" then
		feature_row = row
	elseif name == "default" then
		default_row = row
	end
end
if not feature_row or not default_row then
	fail("workspace rows missing from list output:\n" .. rows)
end

-- The launcher was the default workspace, so its row is marked and feature's is
-- not.
if not default_row:find("🟢", 1, true) then
	fail("current (default) workspace row is not marked:\n" .. default_row)
end
if feature_row:find("🟢", 1, true) then
	fail("non-current (feature) workspace row should not be marked:\n" .. feature_row)
end

-- Names stay left-aligned: field 1 begins with the bare name (marker is a
-- trailing suffix, not a leading prefix/indent).
local function field1_raw(row)
	return vim.split(package.loaded["fzf-lua.utils"].strip_ansi_coloring(row), "\t", { plain = true })[1]
end
if not field1_raw(default_row):match("^default") then
	fail("current workspace name is not left-aligned:\n" .. default_row)
end
if not field1_raw(feature_row):match("^feature") then
	fail("workspace name is not left-aligned:\n" .. feature_row)
end

-- The preview for the feature row runs `jj -R <feature root> log` and succeeds.
local preview_command = captured.opts.preview:gsub("{}", vim.fn.shellescape(feature_row))
local preview = run({ "sh", "-c", preview_command })
if preview == "" then
	fail("feature workspace preview was empty")
end

-- Two windows in the tab, each showing a DIFFERENT file. After switching, each
-- window must show its OWN file from the feature workspace (file1|file2 ->
-- file1|file2, not file1|file1).
vim.cmd("tabnew")
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
vim.cmd("vsplit " .. vim.fn.fnameescape(repo .. "/sample2.txt"))
local wins = vim.api.nvim_tabpage_list_wins(0)
assert_eq(#wins, 2, "two windows in tab before switch")

captured = nil
require("jj-workspace-picker").workspaces()
if not captured then
	fail("picker did not open for two-window switch")
end
captured.opts.actions.enter({ feature_row })

-- Collect the file each window now shows.
local seen = {}
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
	seen[vim.fs.normalize(name)] = true
end
if not seen[vim.fs.normalize(feature .. "/sample.txt")] then
	fail("window showing sample.txt did not switch to the feature copy")
end
if not seen[vim.fs.normalize(feature .. "/sample2.txt")] then
	fail("window showing sample2.txt did not switch to the feature copy (still file1?)")
end
vim.cmd("tabclose")

-- Single-window case: selecting the feature workspace switches the current
-- window to the feature copy of the same relative file.
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
captured = nil
require("jj-workspace-picker").workspaces()
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

-- Root resolution falls back to the file's directory even when the window cwd
-- sits outside the repo: chdir away, open the repo file, and the picker still
-- lists the workspaces instead of erroring.
local outside = vim.fn.tempname()
vim.fn.mkdir(outside, "p")
vim.cmd.cd(vim.fn.fnameescape(outside))
captured = nil
vim.cmd.edit(vim.fn.fnameescape(repo .. "/sample.txt"))
require("jj-workspace-picker").workspaces()
if not captured then
	fail("picker did not open when window cwd was outside the repo")
end
assert_contains(captured.opts.prompt, "jj workspaces", "fallback prompt")

-- Launched entirely outside any jj repo, the picker aborts and does not open.
captured = nil
vim.cmd.cd(vim.fn.fnameescape(outside))
vim.cmd.enew()
require("jj-workspace-picker").workspaces()
if captured then
	fail("picker opened outside a jj repo")
end

vim.fn.delete(outside, "rf")
vim.fn.delete(base, "rf")
print("PASS: jj workspace picker switch")
