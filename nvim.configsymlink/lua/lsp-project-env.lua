local M = {}
local default_timeout = "30s"

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

function M.filter_root_markers(root_markers, excluded)
	local excluded_set = {}
	for _, marker in ipairs(excluded) do
		excluded_set[marker] = true
	end

	local function filter(markers)
		local result = {}
		for _, marker in ipairs(markers) do
			if type(marker) == "table" then
				local group = filter(marker)
				if #group > 0 then
					result[#result + 1] = group
				end
			elseif not excluded_set[marker] then
				result[#result + 1] = marker
			end
		end
		return result
	end

	return filter(root_markers)
end

function M.workspace_root(root_markers, find_root)
	find_root = find_root or vim.fs.root

	return function(bufnr, on_dir)
		local root_dir = find_root(bufnr, root_markers)
		if root_dir then
			on_dir(root_dir)
		end
	end
end

function M.resolve_command(executable, root_dir, direnv, launcher, options)
	options = options or {}
	local env_root = M.find_env_root(root_dir)
	if not env_root or not direnv or direnv == "" or not launcher or launcher == "" then
		return { executable }
	end

	return {
		launcher,
		options.timeout or default_timeout,
		direnv,
		env_root,
		executable,
	}
end

function M.wrap(executable, options)
	options = options or {}

	return function(dispatchers, config)
		local exepath = options.exepath or vim.fn.exepath
		local executable_path = exepath(executable)
		if executable_path == "" then
			executable_path = executable
		end

		local direnv = options.direnv
		if direnv == nil then
			direnv = exepath("direnv")
		end

		local launcher = options.launcher
		if launcher == nil then
			launcher = exepath("lsp-project-env-launcher")
		end
		local command = M.resolve_command(executable_path, config.root_dir, direnv, launcher, options)

		return (options.start or vim.lsp.rpc.start)(command, dispatchers, {
			cwd = config.root_dir,
			env = config.cmd_env,
			detached = config.detached,
		})
	end
end

return M
