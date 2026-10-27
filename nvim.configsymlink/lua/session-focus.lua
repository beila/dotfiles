local M = {}

local function default_session_file()
	return vim.fn.expand("~/.session.vim")
end

local function default_focus_file()
	return vim.fn.expand("~/.session-focus.json")
end

local function apply_focus(focus)
	local tab = tonumber(focus.tab)
	local window = tonumber(focus.window)
	if not tab or tab < 1 or tab > vim.fn.tabpagenr("$") then
		return
	end

	pcall(vim.cmd, "noautocmd tabnext " .. tab)
	if window and window >= 1 and window <= vim.fn.winnr("$") then
		pcall(vim.cmd, "noautocmd " .. window .. "wincmd w")
	end
end

function M.save(session_file, focus_file)
	session_file = session_file or default_session_file()
	focus_file = focus_file or default_focus_file()

	local focus = {
		tab = vim.fn.tabpagenr(),
		window = vim.fn.winnr(),
	}

	vim.cmd("mksession! " .. vim.fn.fnameescape(session_file))
	vim.fn.writefile({ vim.json.encode(focus) }, focus_file)
end

function M.restore(session_file, focus_file)
	session_file = session_file or default_session_file()
	focus_file = focus_file or default_focus_file()

	if vim.fn.filereadable(session_file) == 0 then
		return
	end

	vim.cmd("silent! source " .. vim.fn.fnameescape(session_file))

	if vim.fn.filereadable(focus_file) == 0 then
		return
	end

	local decoded, focus = pcall(vim.json.decode, table.concat(vim.fn.readfile(focus_file), "\n"))
	if not decoded or type(focus) ~= "table" then
		return
	end

	if vim.v.vim_did_enter == 1 then
		apply_focus(focus)
	else
		local group = vim.api.nvim_create_augroup("session_focus_restore", { clear = true })
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			once = true,
			callback = function()
				vim.schedule(function()
					apply_focus(focus)
				end)
			end,
		})
	end
end

return M
