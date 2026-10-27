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

local function yank_after_leader_count(first_digit)
	return function()
		local count = first_digit
		local key = vim.fn.getcharstr()

		while key:match("^%d$") do
			count = count .. key
			key = vim.fn.getcharstr()
		end

		if key == "y" then
			return '"+' .. count .. "y"
		end

		return vim.g.mapleader .. count .. key
	end
end

function M.setup()
	vim.keymap.set("n", "<leader>y", counted_yank("y"), { expr = true })
	for digit = 1, 9 do
		local digit_string = tostring(digit)
		vim.keymap.set("n", "<leader>" .. digit_string, yank_after_leader_count(digit_string), { expr = true })
	end
	vim.keymap.set("v", "<leader>y", [["+y]])
	vim.keymap.set({ "n", "v" }, "<leader>Y", [["+Y]])
end

return M
