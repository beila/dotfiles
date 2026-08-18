local M = {}

local fzf_lua = require("fzf-lua")
local fzf_utils = require("fzf-lua.utils")

local function notify(message, level)
	vim.notify("jj diff: " .. message, level or vim.log.levels.ERROR)
end

local function shell_join(args)
	return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end

local function fileset(path)
	return string.format('"%s"', path:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function run_jj(root, args)
	local cmd = { "jj", "--ignore-working-copy", "--quiet" }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, {
		cwd = root,
		text = true,
		timeout = 5000,
	}):wait()

	if result.code ~= 0 then
		local detail = vim.trim(result.stderr or "")
		notify(detail ~= "" and detail or "command failed")
		return nil
	end

	return vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
end

local function jj_root(start_dir)
	local result = vim.system(
		{ "jj", "--ignore-working-copy", "root" },
		{ cwd = start_dir, text = true, timeout = 2000 }
	)
		:wait()
	if result.code ~= 0 then
		return nil
	end
	return vim.trim(result.stdout)
end

local function source_context()
	local bufnr = vim.api.nvim_get_current_buf()
	local file = ""
	if vim.bo[bufnr].buftype == "" then
		file = vim.api.nvim_buf_get_name(bufnr)
	end
	local start_dir = file ~= "" and vim.fs.dirname(file) or vim.uv.cwd()
	return bufnr, file, jj_root(start_dir)
end

local function selected_commit_ids(selected)
	local ids = {}
	local seen = {}

	for _, line in ipairs(selected) do
		local fields = vim.split(fzf_utils.strip_ansi_coloring(line), "\t", { plain = true })
		local id = fields[#fields]
		if id and id:match("^%x+$") and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end

	return ids
end

local function resolve_range(root, selected)
	local ids = selected_commit_ids(selected)
	if #ids == 0 then
		notify("select at least one revision")
		return nil
	end

	local selected_revset = table.concat(ids, " | ")
	local template = 'commit_id ++ "\\n"'
	local roots = run_jj(root, {
		"log",
		"--no-graph",
		"-r",
		"roots(" .. selected_revset .. ")",
		"-T",
		template,
	})
	local heads = run_jj(root, {
		"log",
		"--no-graph",
		"-r",
		"heads(" .. selected_revset .. ")",
		"-T",
		template,
	})
	if not roots or not heads then
		return nil
	end
	if #roots ~= 1 or #heads ~= 1 then
		notify("selected revisions do not form one ancestry range")
		return nil
	end

	local parents = run_jj(root, {
		"log",
		"--no-graph",
		"-r",
		"parents(" .. roots[1] .. ")",
		"-T",
		template,
	})
	if not parents then
		return nil
	end
	if #parents ~= 1 then
		notify("the oldest selected revision must have exactly one parent")
		return nil
	end

	return parents[1], heads[1]
end

local function preview_command(path)
	local path_arg = path and (" -- " .. vim.fn.shellescape(fileset(path))) or ""
	local commands = {
		[[id=$(printf '%s\n' {} | cut -s -f2 | sed 's/\x1b\[[0-9;]*m//g')]],
		[[test -n "$id" || exit 0]],
	}

	if path then
		table.insert(
			commands,
			[[jj --ignore-working-copy --quiet log --no-graph --color=always -r "$id" -T builtin_log_detailed]]
		)
	else
		table.insert(commands, [[jj --ignore-working-copy --quiet show --summary --color=always "$id"]])
		table.insert(commands, [[printf '\n']])
	end
	table.insert(commands, [[jj --ignore-working-copy --quiet diff --color=always -r "$id"]] .. path_arg)

	return table.concat(commands, "; ")
end

local function log_command(path)
	local args = {
		"jj",
		"--quiet",
		"log",
		"--no-pager",
		"--color=always",
		"-T",
		path and "fzf_oneline_author" or "fzf_oneline",
	}
	if path then
		vim.list_extend(args, { "-r", "all()", "--", fileset(path) })
	end
	return shell_join(args)
end

local function open_codediff(root, source_buf, path, selected)
	local base, target = resolve_range(root, selected)
	if not base then
		return
	end

	local git_result = vim.system(
		{ "git", "rev-parse", "--show-toplevel" },
		{ cwd = root, text = true, timeout = 2000 }
	)
		:wait()
	if git_result.code ~= 0 then
		notify("CodeDiff requires a colocated Git/JJ repository")
		return
	end

	if path then
		if not vim.api.nvim_buf_is_valid(source_buf) then
			notify("source buffer is no longer available")
			return
		end

		local win = vim.fn.bufwinid(source_buf)
		if win ~= -1 then
			vim.api.nvim_set_current_win(win)
		else
			vim.api.nvim_win_set_buf(0, source_buf)
		end
	end

	local args = path and { "file", base, target } or { base, target }
	vim.cmd({ cmd = "CodeDiff", args = args })
end

local function open_picker(root, source_buf, path)
	fzf_lua.fzf_exec(log_command(path), {
		cwd = root,
		prompt = path and "jj file revisions> " or "jj revisions> ",
		preview = preview_command(path),
		fzf_opts = {
			["--ansi"] = true,
			["--delimiter"] = "[\t]",
			["--multi"] = true,
			["--no-sort"] = true,
			["--with-nth"] = "1",
		},
		actions = {
			enter = function(selected)
				open_codediff(root, source_buf, path, selected)
			end,
		},
	})
end

function M.revisions()
	local bufnr, _, root = source_context()
	if not root then
		fzf_lua.git_commits()
		return
	end
	open_picker(root, bufnr)
end

function M.current_file_revisions()
	local bufnr, file, root = source_context()
	if not root then
		fzf_lua.git_bcommits()
		return
	end
	if file == "" then
		notify("current buffer is not a file")
		return
	end

	local relative = vim.fs.relpath(root, file)
	if not relative then
		notify("current file is outside the JJ repository")
		return
	end
	open_picker(root, bufnr, relative)
end

return M
