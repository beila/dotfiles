local M = {}
local default_timeout_ms = 30000

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

function M.workspace_root(root_markers, find_root)
	find_root = find_root or vim.fs.root

	return function(bufnr, on_dir)
		local root_dir = find_root(bufnr, root_markers)
		if root_dir then
			on_dir(root_dir)
		end
	end
end

local function run(command, timeout_ms)
	return vim.system(command, { text = true }):wait(timeout_ms)
end

local function failure_detail(result, timeout_ms)
	if result.code == 124 then
		return ("timed out after %d ms"):format(timeout_ms)
	end

	local stderr = vim.trim(result.stderr or "")
	if stderr ~= "" then
		return stderr:match("[^\r\n]+")
	end

	return "exit code " .. tostring(result.code)
end

function M.resolve_command(executable, root_dir, direnv, options)
	options = options or {}
	local env_root = M.find_env_root(root_dir)
	if not env_root or not direnv or direnv == "" then
		return { executable }
	end

	local timeout_ms = options.timeout_ms or default_timeout_ms
	local ok, result = pcall(options.run or run, { direnv, "exec", env_root, "true" }, timeout_ms)
	if ok and result and result.code == 0 then
		return { direnv, "exec", env_root, executable }
	end

	local detail = ok and result and failure_detail(result, timeout_ms) or tostring(result or "no result")
	return { executable },
		("direnv failed for %s (%s); starting %s without the project environment"):format(env_root, detail, executable)
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
		local command, warning = M.resolve_command(executable_path, config.root_dir, direnv, options)
		if warning then
			(options.notify or vim.notify)(warning, vim.log.levels.WARN)
		end

		return (options.start or vim.lsp.rpc.start)(command, dispatchers, {
			cwd = config.root_dir,
			env = config.cmd_env,
			detached = config.detached,
		})
	end
end

return M
