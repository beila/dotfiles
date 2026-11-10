local M = {}

function M.setup()
	local bridge = vim.fn.expand("~/.dotfiles/bin/clipboard-bridge")
	if vim.fn.executable(bridge) ~= 1 then
		return false
	end
	local active = vim.system({ bridge, "active" }):wait(2000)
	if active.code ~= 0 then
		return false
	end

	local function run(operation, input)
		local result = vim.system({ bridge, operation }, { stdin = input }):wait(12000)
		if result.code ~= 0 then
			vim.notify(result.stderr or "Clipboard bridge failed", vim.log.levels.ERROR)
			return nil
		end
		return result.stdout
	end
	local function copy(lines)
		run("copy", table.concat(lines, "\n"))
	end
	local function paste()
		local text = run("paste") or ""
		return { vim.split(text, "\n", { plain = true }), "v" }
	end
	vim.g.clipboard = {
		name = "local clipboard over SSH",
		copy = {
			["+"] = copy,
			["*"] = copy,
		},
		paste = {
			["+"] = paste,
			["*"] = paste,
		},
		cache_enabled = 0,
	}
	return true
end

return M
