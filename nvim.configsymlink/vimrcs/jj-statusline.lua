local requests = {}

local function set_workspace(winid, request, workspace)
    vim.schedule(function()
        if requests[winid] ~= request or not vim.api.nvim_win_is_valid(winid) then
            return
        end
        vim.w[winid].jj_workspace = workspace
        vim.cmd.redrawstatus()
    end)
end

local function workspace_cwd(winid)
    local ok, cwd = pcall(vim.api.nvim_win_call, winid, function()
        return vim.fn.getcwd()
    end)
    return ok and cwd or nil
end

local function refresh(force)
    local winid = vim.api.nvim_get_current_win()
    local cwd = workspace_cwd(winid)
    if not cwd then
        return
    end

    local previous = requests[winid]
    if not force and previous and previous.cwd == cwd then
        return
    end

    local request = { cwd = cwd }
    requests[winid] = request
    if not previous or previous.cwd ~= cwd then
        vim.w[winid].jj_workspace = ""
    end

    vim.system(
        { "jj", "--ignore-working-copy", "workspace", "root" },
        { cwd = cwd, text = true, timeout = 2000 },
        function(root_result)
            if requests[winid] ~= request then
                return
            end
            if root_result.code ~= 0 then
                set_workspace(winid, request, "")
                return
            end

            local root = vim.trim(root_result.stdout or "")
            if root == "" then
                set_workspace(winid, request, "")
                return
            end

            vim.system({
                "jj", "--ignore-working-copy", "workspace", "list",
                "--color=never", "-T", 'root ++ "\\t" ++ name ++ "\\n"',
            }, {
                cwd = root,
                text = true,
                timeout = 2000,
            }, function(list_result)
                if list_result.code ~= 0 then
                    set_workspace(winid, request, "")
                    return
                end

                local workspace = ""
                for line in (list_result.stdout or ""):gmatch("[^\r\n]+") do
                    local listed_root, name = line:match("^(.-)\t(.*)$")
                    if listed_root and vim.fs.normalize(listed_root) == vim.fs.normalize(root) then
                        workspace = name
                        break
                    end
                end
                set_workspace(winid, request, workspace)
            end)
        end)
end

local group = vim.api.nvim_create_augroup("jj_workspace_statusline", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "DirChanged", "FocusGained", "ShellCmdPost" }, {
    group = group,
    callback = function(args)
        refresh(args.event == "FocusGained" or args.event == "ShellCmdPost")
    end,
})
vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
        requests[tonumber(args.match)] = nil
    end,
})

vim.schedule(refresh)
