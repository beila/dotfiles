-- Dim the text around the cursor paragraph in two levels.
-- The adjacent paragraphs get a light dim. All other paragraphs get a strong dim.
-- This replaces Limelight, because Limelight has only one dim level.

local M = {}

-- 0 keeps the Normal foreground. 1 makes the text the same colour as the background.
M.near = 0.35
M.far = 0.6

local function mix(fg, bg, coeff)
    local out = 0
    for shift = 16, 0, -8 do
        local f = bit.band(bit.rshift(fg, shift), 0xff)
        local b = bit.band(bit.rshift(bg, shift), 0xff)
        out = out + bit.lshift(math.floor(b * coeff + f * (1 - coeff) + 0.5), shift)
    end
    return out
end

function M.set_highlights()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local fg = normal.fg or 0xd0d0d0
    local bg = normal.bg or (vim.o.background == "light" and 0xffffff or 0x000000)
    vim.api.nvim_set_hl(0, "ParagraphDimNear", { fg = mix(fg, bg, M.near) })
    vim.api.nvim_set_hl(0, "ParagraphDimFar", { fg = mix(fg, bg, M.far) })
end

local function blank(lnum)
    return vim.fn.getline(lnum):match("^%s*$") ~= nil
end

-- Find the paragraph that is nearest to lnum in the direction dir.
-- Return its first and last line, or nil when there is no paragraph.
local function paragraph(lnum, dir)
    local last = vim.fn.line("$")
    while lnum >= 1 and lnum <= last and blank(lnum) do
        lnum = lnum + dir
    end
    if lnum < 1 or lnum > last then
        return nil
    end
    local first, final = lnum, lnum
    while first > 1 and not blank(first - 1) do
        first = first - 1
    end
    while final < last and not blank(final + 1) do
        final = final + 1
    end
    return first, final
end

local function clear()
    for _, id in ipairs(vim.w.paragraph_dim_ids or {}) do
        pcall(vim.fn.matchdelete, id)
    end
    vim.w.paragraph_dim_ids = nil
    vim.w.paragraph_dim_key = nil
end

local function update()
    local cur = vim.fn.line(".")
    local first, final = cur, cur
    if not blank(cur) then
        first, final = paragraph(cur, 1)
    end
    local near_top = (paragraph(first - 1, -1)) or first
    local _, near_bottom = paragraph(final + 1, 1)
    near_bottom = near_bottom or final

    -- Do not rebuild the matches when the cursor stays in the same paragraph.
    local key = table.concat({ near_top, first, final, near_bottom, vim.fn.line("$") }, ":")
    if vim.w.paragraph_dim_key == key then
        return
    end
    clear()
    local ids = {}
    local function add(group, pattern)
        table.insert(ids, vim.fn.matchadd(group, pattern, 10))
    end
    add("ParagraphDimFar", ("\\%%<%dl"):format(near_top))
    add("ParagraphDimFar", ("\\%%>%dl"):format(near_bottom))
    if near_top < first then
        add("ParagraphDimNear", ("\\%%>%dl\\%%<%dl"):format(near_top - 1, first))
    end
    if near_bottom > final then
        add("ParagraphDimNear", ("\\%%>%dl\\%%<%dl"):format(final, near_bottom + 1))
    end
    vim.w.paragraph_dim_ids = ids
    vim.w.paragraph_dim_key = key
end

local group = vim.api.nvim_create_augroup("ParagraphDim", { clear = true })

function M.enable()
    vim.w.paragraph_dim_on = true
    update()
end

function M.disable()
    vim.w.paragraph_dim_on = nil
    clear()
end

function M.setup(filetypes)
    M.set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.set_highlights })
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
end

return M
