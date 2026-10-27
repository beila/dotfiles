local M = {}

local function counted_yank(operator)
	return function()
		local count = vim.v.count
		if count == 0 then
			return '"+' .. operator
		end
		return vim.keycode("<Esc>") .. '"+' .. count .. operator
	end
end

function M.setup()
	vim.keymap.set("n", "<leader>y", counted_yank("y"), { expr = true })
	vim.keymap.set("v", "<leader>y", [["+y]])
	vim.keymap.set({ "n", "v" }, "<leader>Y", [["+Y]])
end

return M
