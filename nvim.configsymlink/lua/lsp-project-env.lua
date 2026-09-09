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

function M.read_env(root_dir, variable, direnv, run)
	local env_root = M.find_env_root(root_dir)
	if not env_root or not direnv or direnv == "" then
		return nil
	end

	run = run or function(command)
		return vim.system(command, { text = true }):wait()
	end

	local result = run({ direnv, "exec", env_root, "printenv", variable })
	if result.code ~= 0 then
		return nil
	end

	local value = vim.trim(result.stdout or "")
	return value ~= "" and value or nil
end

function M.before_init_env_setting(variable, setting_path, options)
	options = options or {}

	return function(_, config)
		local direnv = options.direnv or vim.fn.exepath("direnv")
		local value = M.read_env(config.root_dir, variable, direnv, options.run)
		if not value then
			return
		end

		config.settings = config.settings or {}
		local target = config.settings
		for index = 1, #setting_path - 1 do
			local key = setting_path[index]
			target[key] = target[key] or {}
			target = target[key]
		end
		target[setting_path[#setting_path]] = value
	end
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
