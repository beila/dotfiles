local M = {}

function M.copy(text)
	if not text or text == "" then
		return false
	end

	for _, register in ipairs({ "+", '"', "0" }) do
		vim.fn.setreg(register, text)
	end
	return true
end

function M.copy_git_commit(selected, opts)
	local line = selected and selected[1]
	if not line then
		return nil
	end

	local commit_hash
	if opts and type(opts.fn_match_commit_hash) == "function" then
		commit_hash = opts.fn_match_commit_hash(line, opts)
	else
		commit_hash = line:match("[^ ]+")
	end
	if not commit_hash then
		return nil
	end

	commit_hash = vim.trim(commit_hash:gsub("\27%[[0-9;]*m", ""))
	if not M.copy(commit_hash) then
		return nil
	end
	return commit_hash
end

return M
