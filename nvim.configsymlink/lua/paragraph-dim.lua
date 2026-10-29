-- Dim the text around the cursor paragraph in two levels.
-- The adjacent paragraphs get a light dim and keep their syntax colours.
-- All other paragraphs get a strong dim in one colour.
-- Inspired by Limelight (https://github.com/junegunn/limelight.vim).
-- This module replaces Limelight, because Limelight has only one dim level.
-- The colour mix uses the same method as Limelight.

local M = {}

-- 0 keeps the original colour. 1 makes the text the same colour as the background.
M.near = 0.35
M.far = 0.6

local ns = vim.api.nvim_create_namespace("paragraph-dim")
local state = {} -- Key: window ID. Value: the dim regions and the near-text colours.
local dim_groups = {} -- Key: source highlight group. Value: name of the near-dim copy.
M._state = state -- Tests read this table.

local function mix(fg, bg, coeff)
    local out = 0
    for shift = 16, 0, -8 do
        local f = bit.band(bit.rshift(fg, shift), 0xff)
        local b = bit.band(bit.rshift(bg, shift), 0xff)
        out = out + bit.lshift(math.floor(b * coeff + f * (1 - coeff) + 0.5), shift)
    end
    return out
end

local function normal_colours()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local fg = normal.fg or 0xd0d0d0
    local bg = normal.bg or (vim.o.background == "light" and 0xffffff or 0x000000)
    return fg, bg
end

function M.set_highlights()
    local fg, bg = normal_colours()
    vim.api.nvim_set_hl(0, "ParagraphDimNear", { fg = mix(fg, bg, M.near) })
    vim.api.nvim_set_hl(0, "ParagraphDimFar", { fg = mix(fg, bg, M.far) })
    dim_groups = {}
end

-- Find the definition of a highlight group.
-- A tree-sitter capture such as "@markup.heading.1.markdown" can fall back to "@markup.heading".
local function resolve(name)
    while name do
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
        if next(hl) then
            return hl
        end
        name = name:match("^(.+)%.[^.]+$")
    end
    return {}
end

-- Make a copy of a highlight group that has its colours moved to the background colour.
local function dim_group(name)
    if dim_groups[name] then
        return dim_groups[name]
    end
    local hl = resolve(name)
    local fg, bg = normal_colours()
    local copy = {
        fg = mix(hl.fg or fg, bg, M.near),
        bg = hl.bg and mix(hl.bg, bg, M.near) or nil,
        sp = hl.sp and mix(hl.sp, bg, M.near) or nil,
        bold = hl.bold, italic = hl.italic, underline = hl.underline,
        undercurl = hl.undercurl, strikethrough = hl.strikethrough,
    }
    local group = "ParagraphDimNear_" .. name:gsub("[^%w]", "_")
    vim.api.nvim_set_hl(0, group, copy)
    dim_groups[name] = group
    return group
end

local function blank(buf, row)
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    return line == nil or line:match("^%s*$") ~= nil
end

-- Find the paragraph that is nearest to row in the direction dir. Rows start at 0.
-- Return its first and last row, or nil when there is no paragraph.
local function paragraph(buf, row, dir)
    local count = vim.api.nvim_buf_line_count(buf)
    while row >= 0 and row < count and blank(buf, row) do
        row = row + dir
    end
    if row < 0 or row >= count then
        return nil
    end
    local first, last = row, row
    while first > 0 and not blank(buf, first - 1) do
        first = first - 1
    end
    while last < count - 1 and not blank(buf, last + 1) do
        last = last + 1
    end
    return first, last
end

-- Collect the coloured spans of each near row, so that the near dim keeps the syntax colours.
local function near_spans(buf, rows)
    local spans = {}
    for row in pairs(rows) do
        spans[row] = {}
    end
    if vim.treesitter.highlighter.active[buf] then
        local parser = vim.treesitter.get_parser(buf, nil, { error = false })
        if not parser then
            return spans
        end
        local min, max = math.huge, -1
        for row in pairs(rows) do
            min, max = math.min(min, row), math.max(max, row)
        end
        if max < 0 then
            return spans
        end
        parser:parse({ min, max + 1 })
        parser:for_each_tree(function(tree, ltree)
            local query = vim.treesitter.query.get(ltree:lang(), "highlights")
            if not query then
                return
            end
            for id, node in query:iter_captures(tree:root(), buf, min, max + 1) do
                local capture = query.captures[id]
                if not capture:match("^_") and capture ~= "spell" and capture ~= "nospell" and capture ~= "conceal" then
                    local group = dim_group("@" .. capture .. "." .. ltree:lang())
                    local srow, scol, erow, ecol = node:range()
                    for row = math.max(srow, min), math.min(erow, max) do
                        if spans[row] and not (row == erow and ecol == 0 and erow > srow) then
                            table.insert(spans[row], {
                                row == srow and scol or 0,
                                row == erow and ecol or -1,
                                group,
                            })
                        end
                    end
                end
            end
        end)
    elseif vim.bo[buf].syntax ~= "" then
        for row in pairs(rows) do
            local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
            local start, current = 0, nil
            for col = 1, #line + 1 do
                local id = col <= #line and vim.fn.synIDtrans(vim.fn.synID(row + 1, col, 1)) or -1
                if id ~= current then
                    if current and current > 0 then
                        table.insert(spans[row], { start, col - 1, dim_group(vim.fn.synIDattr(current, "name")) })
                    end
                    start, current = col - 1, id
                end
            end
        end
    end
    return spans
end

-- Calculate the dim regions for the cursor position of the current window.
local function update()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local cur = vim.api.nvim_win_get_cursor(win)[1] - 1
    local first, last
    if blank(buf, cur) then
        -- Between paragraphs, show the paragraph above and the paragraph below, as Limelight does.
        first = (paragraph(buf, cur, -1)) or cur
        local _, below = paragraph(buf, cur, 1)
        last = below or cur
    else
        first, last = paragraph(buf, cur, 1)
    end
    local near_top = (paragraph(buf, first - 1, -1)) or first
    local _, near_bottom = paragraph(buf, last + 1, 1)
    near_bottom = near_bottom or last

    local key = table.concat({ buf, near_top, first, last, near_bottom, vim.b[buf].changedtick }, ":")
    local old = state[win]
    if old and old.key == key then
        return
    end
    local rows = {}
    for row = near_top, first - 1 do
        rows[row] = true
    end
    for row = last + 1, near_bottom do
        rows[row] = true
    end
    state[win] = {
        key = key, buf = buf,
        near_top = near_top, first = first, last = last, near_bottom = near_bottom,
        spans = near_spans(buf, rows),
    }
    vim.api.nvim__redraw({ win = win, valid = false })
end

local function draw_line(st, buf, row)
    local function mark(scol, ecol, group, priority)
        local opts = { hl_group = group, priority = priority, ephemeral = true }
        if ecol < 0 then
            opts.end_row, opts.end_col = row + 1, 0
        else
            opts.end_row, opts.end_col = row, ecol
        end
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, scol, opts)
    end
    if row < st.near_top or row > st.near_bottom then
        -- Use a priority above tree-sitter (100) and LSP semantic tokens (125).
        mark(0, -1, "ParagraphDimFar", 200)
    elseif row < st.first or row > st.last then
        mark(0, -1, "ParagraphDimNear", 140)
        for _, span in ipairs(st.spans[row] or {}) do
            mark(span[1], span[2], span[3], 150)
        end
    end
end

local group = vim.api.nvim_create_augroup("ParagraphDim", { clear = true })

function M.enable()
    vim.w.paragraph_dim_on = true
    state[vim.api.nvim_get_current_win()] = nil
    update()
end

function M.disable()
    local win = vim.api.nvim_get_current_win()
    vim.w.paragraph_dim_on = nil
    if state[win] then
        state[win] = nil
        vim.api.nvim__redraw({ win = win, valid = false })
    end
end

function M.setup(filetypes)
    M.set_highlights()
    vim.api.nvim_set_decoration_provider(ns, {
        on_win = function(_, win, buf)
            local st = state[win]
            return st ~= nil and st.buf == buf
        end,
        on_line = function(_, win, buf, row)
            draw_line(state[win], buf, row)
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            M.set_highlights()
            for win in pairs(state) do
                state[win].key = nil
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function()
            if filetypes[vim.bo.filetype] then
                M.enable()
            else
                M.disable()
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
        group = group,
        callback = function()
            if vim.w.paragraph_dim_on then
                update()
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            state[tonumber(args.match)] = nil
        end,
    })
end

return M
