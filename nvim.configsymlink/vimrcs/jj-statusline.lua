local requests = {}
local next_request = 0

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

local function refresh(winid)
    winid = winid or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(winid) then
        return
    end

    next_request = next_request + 1
    local request = next_request
    requests[winid] = request
    vim.w[winid].jj_workspace = ""

    local cwd = workspace_cwd(winid)
    if not cwd then
        return
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

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "DirChanged", "FocusGained", "ShellCmdPost" }, {
    group = vim.api.nvim_create_augroup("jj_workspace_statusline", { clear = true }),
    callback = function()
        refresh()
    end,
})

vim.schedule(refresh)
