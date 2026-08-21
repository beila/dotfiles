require("codediff").setup({
	diff = {
		cycle_next_hunk = false,
		gutter_signs = {
			insert_text = "+",
			delete_text = "-",
			highlight_numbers = true,
		},
	},
})

local origins = {}
local group = vim.api.nvim_create_augroup("CodeDiffReturnToOrigin", { clear = true })

vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "CodeDiffOpen",
	callback = function(args)
		local tabpage = args.data and args.data.tabpage
		local origin = vim.api.nvim_list_tabpages()[vim.fn.tabpagenr("#")]
		if tabpage and origin and origin ~= tabpage then
			origins[tabpage] = origin
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "CodeDiffClose",
	callback = function(args)
		local tabpage = args.data and args.data.tabpage
		local origin = tabpage and origins[tabpage]
		if not origin then
			return
		end
		origins[tabpage] = nil

		vim.schedule(function()
			if not vim.api.nvim_tabpage_is_valid(tabpage) and vim.api.nvim_tabpage_is_valid(origin) then
				vim.api.nvim_set_current_tabpage(origin)
			end
		end)
	end,
})
