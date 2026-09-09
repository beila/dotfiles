local function fail(message)
	error("test_lsp_project_env: " .. message, 0)
end

local function assert_eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		fail(label .. ": expected " .. vim.inspect(expected) .. " got " .. vim.inspect(actual))
	end
end

local script = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fs.dirname(script)
package.path = config_root .. "/lua/?.lua;" .. package.path
package.loaded["lsp-project-env"] = dofile(config_root .. "/lua/lsp-project-env.lua")

local project_env = require("lsp-project-env")
local base = vim.fn.tempname()
local repo = base .. "/IgnitionX"
local android = repo .. "/portingplatforms/android/ignition-android"
local source = android .. "/ignitionshared/src/main/java"
vim.fn.mkdir(source, "p")

assert_eq(project_env.find_env_root(source), nil, "project without envrc")

vim.fn.writefile({ "use flake ../../..#android" }, android .. "/.envrc")
assert_eq(project_env.find_env_root(source), android, "Android env root")
assert_eq(project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv"), {
	"/nix/store/direnv/bin/direnv",
	"exec",
	android,
	"/nix/store/jdtls/bin/jdtls",
}, "direnv command")
assert_eq(
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, ""),
	{ "/nix/store/jdtls/bin/jdtls" },
	"missing direnv fallback"
)

local nested = android .. "/ignitionshared"
vim.fn.writefile({ "use flake" }, nested .. "/.envrc")
assert_eq(project_env.find_env_root(source), nested, "nearest envrc")

vim.fn.delete(base, "rf")
print("PASS: LSP project environment selection")
