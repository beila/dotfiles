local M = {}

local fzf_lua = require("fzf-lua")
local fzf_utils = require("fzf-lua.utils")

local line_history_tempfiles = {}

local function notify(message, level)
	vim.notify("jj diff: " .. message, level or vim.log.levels.ERROR)
end

local function shell_join(args)
	return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end

local function fileset(path)
	return string.format('"%s"', path:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function run_command(root, cmd, report_error)
	local result = vim.system(cmd, {
		cwd = root,
		text = true,
		timeout = 5000,
	}):wait()

	if result.code ~= 0 then
		if report_error ~= false then
			local detail = vim.trim(result.stderr or "")
			notify(detail ~= "" and detail or "command failed")
		end
		return nil
	end

	return result.stdout or ""
end

local function run_jj(root, args, report_error)
	local cmd = { "jj", "--ignore-working-copy", "--quiet" }
	vim.list_extend(cmd, args)
	local output = run_command(root, cmd, report_error)
	return output and vim.split(output, "\n", { plain = true, trimempty = true }) or nil
end

local function clear_line_history_tempfiles()
	for path in pairs(line_history_tempfiles) do
		vim.fn.delete(path)
		line_history_tempfiles[path] = nil
	end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("JjDiffPickerCleanup", { clear = true }),
	callback = clear_line_history_tempfiles,
})

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

local function build_line_history(root, path, line_range)
	local commit_output = run_command(root, {
		"jj",
		"--quiet",
		"log",
		"--no-graph",
		"-r",
		"@",
		"-T",
		'commit_id ++ "\n"',
	})
	local start_commit = commit_output and vim.trim(commit_output) or ""
	if not start_commit:match("^%x+$") then
		notify("could not resolve the current JJ commit")
		return nil
	end

	local range_arg = string.format("-L%d,%d:%s", line_range[1], line_range[2], path)
	local output = run_command(root, {
		"git",
		"--no-pager",
		"log",
		"--color=always",
		"--no-merges",
		"--date=short",
		"--format=%x1e%H%ncommit %C(yellow)%H%C(reset)%nAuthor: %an <%ae>%nDate: %ad%n%n    %s",
		range_arg,
		start_commit,
	})
	if not output then
		return nil
	end

	local ids = {}
	local seen = {}
	for id in output:gmatch("\30(%x+)") do
		if not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		notify("no revisions found for the selected lines", vim.log.levels.INFO)
		return nil
	end

	clear_line_history_tempfiles()
	local preview_path = vim.fn.tempname()
	local write_result = vim.fn.writefile(vim.split(output, "\n", { plain = true }), preview_path, "b")
	if write_result ~= 0 then
		vim.fn.delete(preview_path)
		notify("could not cache the line-history preview")
		return nil
	end
	line_history_tempfiles[preview_path] = true

	return {
		active = true,
		range = line_range,
		revset = table.concat(ids, " | "),
		preview_path = preview_path,
	}
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

local function selected_ids(selected, field, pattern)
	local ids = {}
	local seen = {}

	for _, line in ipairs(selected) do
		local fields = vim.split(fzf_utils.strip_ansi_coloring(line), "\t", { plain = true })
		local id = fields[field]
		if id and id ~= "" and (not pattern or id:match(pattern)) and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end

	return ids
end

local function selected_change_ids(selected)
	return selected_ids(selected, 2)
end

local function selected_commit_ids(selected)
	return selected_ids(selected, 4, "^%x+$")
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

local function configured_log_revset(root)
	local lines = run_jj(root, { "config", "get", "revsets.log" }, false)
	return lines and #lines > 0 and table.concat(lines, "\n") or "log()"
end

local function active_revset(state)
	if state.line_history and state.line_history.active then
		return state.line_history.revset
	end
	return state.full_log and state.full_revset or state.default_revset
end

local function log_template(state)
	local template = state.full_log and "fzf_oneline_author" or "fzf_oneline"
	return state.files and (template .. " ++ fzf_files_suffix") or template
end

local function log_args(state, color)
	local args = {
		"log",
		"--no-pager",
		"--color=" .. color,
		"-T",
		log_template(state),
		"-r",
		active_revset(state),
	}
	if state.path then
		vim.list_extend(args, { "--", fileset(state.path) })
	end
	return args
end

local function preview_command(state)
	if state.line_history and state.line_history.active then
		return table.concat({
			[[commit=$(printf '%s\n' {} | cut -s -f4 | sed 's/\x1b\[[0-9;]*m//g')]],
			[[test -n "$commit" || exit 0]],
			[[awk -v commit="$commit" 'BEGIN { marker = sprintf("%c", 30) } substr($0, 1, 1) == marker { selected = index(substr($0, 2), commit) == 1; next } selected { print }' ]]
				.. vim.fn.shellescape(state.line_history.preview_path),
		}, "; ")
	end

	local commands = {
		[[id=$(printf '%s\n' {} | cut -s -f2 | sed 's/\x1b\[[0-9;]*m//g')]],
		[[path=$(printf '%s\n' {} | cut -s -f3 | sed 's/\x1b\[[0-9;]*m//g')]],
		[[test -n "$id" || exit 0]],
	}

	if state.files then
		table.insert(
			commands,
			[[jj --ignore-working-copy --quiet log --no-graph --color=always -r "$id" -T builtin_log_detailed]]
		)
	else
		table.insert(commands, [[jj --ignore-working-copy --quiet show --summary --color=always "$id"]])
		table.insert(commands, [[printf '\n']])
	end

	if state.path then
		table.insert(commands, [[test -n "$path" || path=]] .. vim.fn.shellescape(state.path))
	end
	table.insert(
		commands,
		[[if test -n "$path"; then jj --ignore-working-copy --quiet diff --color=always -r "$id" -- "$path"; else jj --ignore-working-copy --quiet diff --color=always -r "$id"; fi]]
	)
	return table.concat(commands, "; ")
end

local function log_command(state)
	local args = { "jj", "--quiet" }
	vim.list_extend(args, log_args(state, "always"))
	return shell_join(args)
end

local function find_position(state, change_id)
	if not change_id then
		return nil
	end
	local lines = run_jj(state.root, log_args(state, "never"), false)
	for index, line in ipairs(lines or {}) do
		if selected_change_ids({ line })[1] == change_id then
			return index
		end
	end
	return nil
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

local function copy_commit_ids(selected)
	local ids = selected_commit_ids(selected)
	if #ids == 0 then
		notify("select at least one revision")
		return
	end

	local text = table.concat(ids, "\n")
	local registers = {}
	if vim.o.clipboard:match("unnamed") then
		table.insert(registers, "*")
	end
	if vim.o.clipboard:match("unnamedplus") then
		table.insert(registers, "+")
	end
	if #registers == 0 then
		table.insert(registers, '"')
	end
	for _, register in ipairs(registers) do
		vim.fn.setreg(register, text)
	end
	vim.fn.setreg("0", text)
	notify(
		string.format("%d commit ID%s copied to register %s", #ids, #ids == 1 and "" or "s", registers[1]),
		vim.log.levels.INFO
	)
end

local function picker_header(state)
	local history_checked = state.full_log
	local history_label = state.path and "all file revisions" or "full log"
	if state.line_history then
		history_checked = state.line_history.active
		history_label = string.format("lines %d-%d", state.line_history.range[1], state.line_history.range[2])
	end

	return string.format(
		"[%s] %s (ctrl-h)  [%s] files (ctrl-s)  insert after (ctrl-o)  copy commit-id (ctrl-x)",
		history_checked and "x" or " ",
		history_label,
		state.files and "x" or " "
	)
end

local open_picker

local function reopen_action(state, mutate)
	return {
		fn = function(selected, opts)
			local change_id = selected_change_ids(selected)[1]
			mutate()
			state.query = opts.last_query
			state.pos = find_position(state, change_id) or tonumber(selected[2])
			open_picker(state)
		end,
		exec_silent = true,
		field_index = "{} $FZF_POS",
		header = false,
	}
end

open_picker = function(state)
	fzf_lua.fzf_exec(log_command(state), {
		cwd = state.root,
		prompt = state.line_history and state.line_history.active and "jj line revisions> "
			or state.path and "jj file revisions> "
			or "jj revisions> ",
		query = state.query,
		locate = state.pos ~= nil,
		__locate_pos = state.pos,
		preview = preview_command(state),
		fzf_opts = {
			["--ansi"] = true,
			["--delimiter"] = "[\t]",
			["--header"] = picker_header(state),
			["--multi"] = true,
			["--no-sort"] = true,
			["--with-nth"] = "1",
		},
		actions = {
			enter = function(selected)
				open_codediff(state.root, state.source_buf, state.path, selected)
			end,
			["ctrl-h"] = reopen_action(state, function()
				if state.line_history then
					state.line_history.active = not state.line_history.active
				else
					state.full_log = not state.full_log
				end
			end),
			["ctrl-s"] = reopen_action(state, function()
				state.files = not state.files
			end),
			["ctrl-o"] = {
				fn = function(selected)
					local change_id = selected_change_ids(selected)[1]
					if not change_id then
						notify("select a revision to insert after")
						return
					end
					run_jj(state.root, { "new", "--no-edit", "--after", change_id })
				end,
				field_index = "{}",
				header = false,
				reload = true,
			},
			["ctrl-x"] = {
				fn = copy_commit_ids,
				exec_silent = true,
				header = false,
			},
		},
	})
end

local function new_state(root, source_buf, path, line_history)
	return {
		root = root,
		source_buf = source_buf,
		path = path,
		line_history = line_history,
		default_revset = configured_log_revset(root),
		full_revset = path and "all()" or "::workspace_view()",
		full_log = path ~= nil,
		files = false,
	}
end

function M.revisions()
	local bufnr, _, root = source_context()
	if not root then
		fzf_lua.git_commits()
		return
	end
	open_picker(new_state(root, bufnr))
end

function M.current_file_revisions(line_range)
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

	local line_history
	if line_range then
		if vim.bo[bufnr].modified then
			notify("save the current buffer before opening line history")
			return
		end
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		local first = math.min(line_count, math.max(1, math.min(line_range[1], line_range[2])))
		local last = math.min(line_count, math.max(line_range[1], line_range[2]))
		line_history = build_line_history(root, relative, { first, last })
		if not line_history then
			return
		end
	end

	open_picker(new_state(root, bufnr, relative, line_history))
end

return M
