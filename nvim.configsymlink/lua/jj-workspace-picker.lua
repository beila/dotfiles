local M = {}

local fzf_lua = require("fzf-lua")
local fzf_utils = require("fzf-lua.utils")

local function notify(message, level)
	vim.notify("jj workspace: " .. message, level or vim.log.levels.ERROR)
end

-- Resolve the workspace root that contains `start_dir`. `jj workspace root`
-- reports the root of the workspace the directory lives in, which is what we
-- rebase the file path against; `jj root` would collapse every workspace to
-- the shared repository root.
local function workspace_root(start_dir)
	local result = vim.system(
		{ "jj", "--ignore-working-copy", "workspace", "root" },
		{ cwd = start_dir, text = true, timeout = 2000 }
	):wait()
	if result.code ~= 0 then
		return nil
	end
	return vim.trim(result.stdout)
end

-- The window we launched from decides both the file to reopen and the
-- workspace we are switching away from.
local function source_context()
	local winid = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local file = ""
	if vim.bo[bufnr].buftype == "" then
		file = vim.api.nvim_buf_get_name(bufnr)
	end
	local start_dir = file ~= "" and vim.fs.dirname(file) or vim.uv.cwd()
	return winid, file, workspace_root(start_dir)
end

-- Each row is `<name>\t<root>`: fzf shows only the name (--with-nth=1) and the
-- selection carries the root in field 2. A single-workspace repo still renders
-- its one row.
local function list_command(color)
	local args = {
		"jj",
		"--ignore-working-copy",
		"workspace",
		"list",
		"--color=" .. color,
		"-T",
		'name ++ "\\t" ++ if(root, root, "") ++ "\\n"',
	}
	return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end

-- Preview the target workspace's own `jj log`, run with `-R <root>` so it
-- reflects that workspace's working-copy commit rather than the launcher's.
local function preview_command()
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

function M.workspaces()
	local source_win, source_file, source_root = source_context()
	if not source_root then
		notify("current window is not inside a JJ workspace")
		return
	end

	fzf_lua.fzf_exec(list_command("always"), {
		cwd = source_root,
		prompt = "jj workspaces> ",
		preview = preview_command(),
		fzf_opts = {
			["--ansi"] = true,
			["--delimiter"] = "[\t]",
			["--header"] = "switch tab to workspace (same file, chosen workspace)",
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
				switch_tab_to_workspace(source_win, source_root, source_file, target_root)
			end,
		},
	})
end

return M
