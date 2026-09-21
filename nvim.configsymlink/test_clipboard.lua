local storage = {
	["+"] = "",
	["*"] = "",
}

local function copy(register)
	return function(lines)
		storage[register] = table.concat(lines, "\n")
	end
end

local function paste(register)
	return function()
		return vim.split(storage[register], "\n", { plain = true }), "v"
	end
end

vim.g.clipboard = {
	name = "test clipboard",
	copy = {
		["+"] = copy("+"),
		["*"] = copy("*"),
	},
	paste = {
		["+"] = paste("+"),
		["*"] = paste("*"),
	},
	cache_enabled = 0,
}

return storage
