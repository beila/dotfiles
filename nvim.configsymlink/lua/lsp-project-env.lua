local M = {}

function M.find_env_root(root_dir)
	if not root_dir or root_dir == "" then
		return nil
	end

	local envrc = vim.fs.find(".envrc", {
		path = root_dir,
		upward = true,
		limit = 1,
	})[1]

	return envrc and vim.fs.dirname(envrc) or nil
end

function M.resolve_command(executable, root_dir, direnv)
	local env_root = M.find_env_root(root_dir)
	if env_root and direnv and direnv ~= "" then
		return { direnv, "exec", env_root, executable }
	end

	return { executable }
end

function M.wrap(executable)
	return function(dispatchers, config)
		local executable_path = vim.fn.exepath(executable)
		if executable_path == "" then
			executable_path = executable
		end

		local command = M.resolve_command(executable_path, config.root_dir, vim.fn.exepath("direnv"))
		return vim.lsp.rpc.start(command, dispatchers, {
			cwd = config.root_dir,
			env = config.cmd_env,
			detached = config.detached,
		})
	end
end

return M
