local function fail(message)
	error("test_jj_diff_picker: " .. message, 0)
end

local function assert_contains(text, expected, label)
	if not text:find(expected, 1, true) then
		fail(label .. ": missing " .. vim.inspect(expected))
	end
end

local function assert_not_contains(text, unexpected, label)
	if text:find(unexpected, 1, true) then
		fail(label .. ": unexpectedly contained " .. vim.inspect(unexpected))
	end
end

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")

local git_env = vim.tbl_extend("force", vim.fn.environ(), {
	GIT_AUTHOR_NAME = "JJ Picker Test",
	GIT_AUTHOR_EMAIL = "jj-picker@example.com",
	GIT_COMMITTER_NAME = "JJ Picker Test",
	GIT_COMMITTER_EMAIL = "jj-picker@example.com",
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

local file = repo .. "/sample.txt"

git({ "init", "-q" })
vim.fn.writefile({ "header", "target one", "target two", "footer" }, file)
git({ "add", "sample.txt" })
git({ "commit", "-q", "-m", "introduce target" })
local introduction = git({ "rev-parse", "HEAD" })

vim.fn.writefile({ "header", "inserted one", "inserted two", "target one", "target two", "footer" }, file)
git({ "add", "sample.txt" })
git({ "commit", "-q", "-m", "shift target lines" })

vim.fn.writefile({ "header", "inserted one", "inserted two", "target one changed", "target two", "footer" }, file)
git({ "add", "sample.txt" })
git({ "commit", "-q", "-m", "change target" })
local target_change = git({ "rev-parse", "HEAD" })

vim.fn.writefile(
	{ "header", "inserted one", "inserted two", "target one changed", "target two", "footer changed" },
	file
)
git({ "add", "sample.txt" })
git({ "commit", "-q", "-m", "change footer" })
local unrelated_change = git({ "rev-parse", "HEAD" })

run({ "jj", "git", "init", "--colocate", "." })

local captured
package.loaded["fzf-lua"] = {
	fzf_exec = function(contents, opts)
		captured = { contents = contents, opts = opts }
	end,
	git_bcommits = function()
		fail("unexpected Git fallback")
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

vim.cmd.edit(vim.fn.fnameescape(file))
require("jj-diff-picker").current_file_revisions({ 4, 5 })

if not captured then
	fail("picker did not open")
end
assert_contains(captured.contents, introduction, "line-history revset")
assert_contains(captured.contents, target_change, "line-history revset")
assert_not_contains(captured.contents, unrelated_change, "line-history revset")
assert_contains(captured.opts.prompt, "line revisions", "line-history prompt")
assert_contains(captured.opts.fzf_opts["--header"], "lines 4-5", "line-history header")

local rows = run({ "sh", "-c", captured.contents })
local target_row
for row in rows:gmatch("[^\n]+") do
	local fields = vim.split(package.loaded["fzf-lua.utils"].strip_ansi_coloring(row), "\t", { plain = true })
	if fields[4] and target_change:find(fields[4], 1, true) == 1 then
		target_row = row
		break
	end
end
if not target_row then
	fail("target revision is missing from rendered JJ rows:\n" .. rows)
end

local preview_command = captured.opts.preview:gsub("{}", vim.fn.shellescape(target_row))
local preview = run({ "sh", "-c", preview_command })
assert_contains(preview, "target one changed", "range preview")
assert_not_contains(preview, "footer changed", "range preview")

captured.opts.actions["ctrl-h"].fn({ target_row, "1" }, { last_query = "" })
assert_contains(captured.opts.prompt, "file revisions", "unfiltered prompt")
assert_contains(captured.opts.fzf_opts["--header"], "[ ] lines 4-5", "unfiltered header")
assert_contains(captured.contents, "all()", "unfiltered revset")

vim.fn.delete(repo, "rf")
print("PASS: jj diff picker line history")
