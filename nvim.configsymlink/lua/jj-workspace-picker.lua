local M = {}

local fzf_lua = require("fzf-lua")
local fzf_utils = require("fzf-lua.utils")

local function notify(message, level)
	vim.notify("jj: " .. message, level or vim.log.levels.ERROR)
end

-- Run a jj subcommand from `start_dir` and return its trimmed stdout, or
-- nil + a reason. Wrapped in pcall because vim.system throws when the jj
-- executable cannot be spawned (e.g. not on Neovim's PATH under a GUI launch).
local function run_jj(start_dir, args)
	local cmd = { "jj", "--ignore-working-copy" }
	vim.list_extend(cmd, args)
	local ok, result = pcall(function()
		return vim.system(cmd, { cwd = start_dir, text = true, timeout = 5000 }):wait()
	end)
	if not ok then
		return nil, "cannot run jj (" .. tostring(result) .. ")"
	end
	if result.code ~= 0 then
		local detail = vim.trim(result.stderr or "")
		return nil, detail ~= "" and detail or ("jj exited " .. tostring(result.code))
	end
	local out = vim.trim(result.stdout or "")
	if out == "" then
		return nil, "empty output"
	end
	return out
end

-- Resolve the workspace root that contains `start_dir`. `jj workspace root`
-- reports the root of the workspace the directory lives in, which is what we
-- rebase the file path against. If that subcommand is unavailable or errors on
-- this jj version, fall back to `jj root` (the shared repository root) so the
-- picker still works — the branch dialog's own gate uses `jj root`, so this
-- keeps the two entry points consistent. Returns root, or nil + a reason.
local function probe_workspace_root(start_dir)
	if not start_dir or start_dir == "" or vim.fn.isdirectory(start_dir) == 0 then
		return nil, "no directory to probe"
	end
	local root = run_jj(start_dir, { "workspace", "root" })
	if root then
		return root
	end
	local fallback, reason = run_jj(start_dir, { "root" })
	if fallback then
		return fallback
	end
	return nil, reason
end

-- Probe several directories so a window whose cwd sits outside the repo (but
-- whose file lives inside it) — or the reverse — still resolves. Mirrors how
-- jj-statusline.lua falls back to the window cwd.
local function resolve_workspace_root(winid, file)
	local candidates = {}
	local function add(dir)
		if dir and dir ~= "" then
			candidates[#candidates + 1] = dir
		end
	end
	if file ~= "" then
		add(vim.fs.dirname(file))
	end
	local ok, win_cwd = pcall(vim.api.nvim_win_call, winid, function()
		return vim.fn.getcwd()
	end)
	if ok then
		add(win_cwd)
	end
	add(vim.uv.cwd())

	local last_reason = "no directory to probe"
	for _, dir in ipairs(candidates) do
		local root, reason = probe_workspace_root(dir)
		if root then
			return root
		end
		last_reason = reason
	end
	return nil, last_reason
end

-- The window we launched from decides both the file to reopen and the
-- workspace we are switching away from. Threaded through both pickers so a
-- ctrl-b toggle back to workspaces still knows where it started.
local function source_context()
	local winid = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local file = ""
	if vim.bo[bufnr].buftype == "" then
		file = vim.api.nvim_buf_get_name(bufnr)
	end
	local root, reason = resolve_workspace_root(winid, file)
	return winid, file, root, reason
end

local function shell_join(args)
	return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end

-- Each workspace row is `<name> <marker>\t<root>`: fzf shows only the first
-- field (--with-nth=1) and the selection carries the root in field 2. The
-- current workspace (the one the picker was launched from) gets a trailing 🟢
-- emoji; the marker sits AFTER the name so every name stays left-aligned in
-- the same column. A single-workspace repo still renders its one row.
local CURRENT_MARKER = "🟢"

local function workspace_list_command(color, current_root)
	local jj = shell_join({
		"jj",
		"--ignore-working-copy",
		"workspace",
		"list",
		"--color=" .. color,
		"-T",
		'name ++ "\\t" ++ if(root, root, "") ++ "\\n"',
	})
	-- Append the current-workspace marker to the name of the row whose
	-- (color-stripped) root matches the launcher's root; leave the rest as-is
	-- so all names start in the same column.
	local awk = string.format(
		[[awk -F'\t' -v cur=%s 'BEGIN{OFS="\t"} { bare=$2; gsub(/\x1b\[[0-9;]*m/,"",bare); ]]
			.. [[if (bare==cur) $1=$1 " %s"; print }']],
		vim.fn.shellescape(current_root or ""),
		CURRENT_MARKER
	)
	return jj .. " | " .. awk
end

-- Preview the target workspace's own `jj log`, run with `-R <root>` so it
-- reflects that workspace's working-copy commit rather than the launcher's.
local function workspace_preview_command()
	return table.concat({
		[[root=$(printf '%s\n' {} | cut -s -f2 | sed 's/\x1b\[[0-9;]*m//g')]],
		[[test -n "$root" || exit 0]],
		[[jj --ignore-working-copy --quiet -R "$root" log --color=always]],
	}, "; ")
end

local function selected_root(selected)
	local line = selected and selected[1]
	if not line then
		return nil
	end
	local fields = vim.split(fzf_utils.strip_ansi_coloring(line), "\t", { plain = true })
	local root = fields[2]
	if root and root ~= "" then
		return vim.trim(root)
	end
	return nil
end

-- The bookmark (branch) picker mirrors zsh `_jb`: `jj bookmark list` with the
-- first whitespace field as the bookmark name. The preview logs the
-- bookmark's boundary against all bookmarks.
local function bookmark_list_command(color)
	return shell_join({
		"jj",
		"--ignore-working-copy",
		"--quiet",
		"bookmark",
		"list",
		"--color=" .. color,
	})
end

local function bookmark_preview_command()
	return table.concat({
		[[name=$(printf '%s\n' {} | awk '{gsub(/:$/,"",$1); gsub(/\x1b\[[0-9;]*m/,"",$1); print $1}')]],
		[[test -n "$name" || exit 0]],
		[[jj --ignore-working-copy --quiet log --color=always -r "unique_boundary($name, bookmarks() | remote_bookmarks())"]],
	}, "; ")
end

local function selected_bookmark(selected)
	local line = selected and selected[1]
	if not line then
		return nil
	end
	local stripped = fzf_utils.strip_ansi_coloring(line)
	local name = stripped:match("^%s*([^%s:]+)")
	return name
end

-- Point every window in the current tab at the equivalent file in the chosen
-- workspace. The relative path is taken from the launcher window's file within
-- its own workspace, then rebased onto the target workspace root.
local function switch_tab_to_workspace(source_win, source_root, source_file, target_root)
	if vim.fs.normalize(target_root) == vim.fs.normalize(source_root) then
		notify("already in this workspace", vim.log.levels.INFO)
		return
	end

	local relative
	if source_file ~= "" then
		relative = vim.fs.relpath(source_root, source_file)
		if not relative then
			notify("current file is outside its workspace; cannot map it across workspaces")
			return
		end
	end

	local target_path
	if relative then
		target_path = vim.fs.joinpath(target_root, relative)
		if vim.fn.filereadable(target_path) == 0 then
			notify(string.format("%s does not exist in the chosen workspace", relative), vim.log.levels.WARN)
			return
		end
	end

	if not vim.api.nvim_win_is_valid(source_win) then
		notify("source window is no longer available")
		return
	end

	local windows = vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(source_win))
	for _, win in ipairs(windows) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_call(win, function()
				-- Anchor each window's cwd in the target workspace so relative
				-- pickers, LSP root detection, and the jj statusline follow.
				vim.cmd.lcd(vim.fn.fnameescape(target_root))
				if target_path then
					vim.cmd.edit(vim.fn.fnameescape(target_path))
				end
			end)
		end
	end
end

-- Forward declarations so the two pickers can hand off to each other via
-- ctrl-b, matching the zsh `_jbb` <-> `_jb` toggle.
local open_workspaces
local open_bookmarks

-- ctrl-b re-dispatches on the fzf-lua main loop; scheduling avoids nesting a
-- new fzf inside the closing one's callback.
local function toggle_action(open, ctx)
	return function()
		vim.schedule(function()
			open(ctx)
		end)
	end
end

open_workspaces = function(ctx)
	fzf_lua.fzf_exec(workspace_list_command("always", ctx.source_root), {
		cwd = ctx.source_root,
		prompt = "jj workspaces> ",
		preview = workspace_preview_command(),
		fzf_opts = {
			["--ansi"] = true,
			["--delimiter"] = "[\t]",
			["--header"] = "☑ workspaces (ctrl-b) — switch tab to workspace (same file)",
			["--no-sort"] = true,
			["--with-nth"] = "1",
		},
		actions = {
			enter = function(selected)
				local target_root = selected_root(selected)
				if not target_root then
					notify("select a workspace")
					return
				end
				switch_tab_to_workspace(ctx.source_win, ctx.source_root, ctx.source_file, target_root)
			end,
			["ctrl-b"] = toggle_action(open_bookmarks, ctx),
		},
	})
end

open_bookmarks = function(ctx)
	fzf_lua.fzf_exec(bookmark_list_command("always"), {
		cwd = ctx.source_root,
		prompt = "jj bookmarks> ",
		preview = bookmark_preview_command(),
		fzf_opts = {
			["--ansi"] = true,
			["--header"] = "☐ workspaces (ctrl-b) — copy bookmark name",
			["--no-sort"] = true,
		},
		actions = {
			enter = function(selected)
				local name = selected_bookmark(selected)
				if not name then
					notify("select a bookmark")
					return
				end
				vim.fn.setreg('"', name)
				vim.fn.setreg("0", name)
				notify(string.format("bookmark %q copied", name), vim.log.levels.INFO)
			end,
			["ctrl-b"] = toggle_action(open_workspaces, ctx),
		},
	})
end

local function new_context()
	local source_win, source_file, source_root, reason = source_context()
	if not source_root then
		notify("current window is not inside a JJ workspace (" .. (reason or "unknown") .. ")")
		return nil
	end
	return {
		source_win = source_win,
		source_file = source_file,
		source_root = source_root,
	}
end

function M.workspaces()
	local ctx = new_context()
	if ctx then
		open_workspaces(ctx)
	end
end

function M.bookmarks()
	local ctx = new_context()
	if ctx then
		open_bookmarks(ctx)
	end
end

return M
