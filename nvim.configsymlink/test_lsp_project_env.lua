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

vim.fn.writefile({
	"pushd ../../.. >/dev/null",
	"use flake .#android",
	"popd >/dev/null",
}, android .. "/.envrc")
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

local command
local function successful_run(actual)
	command = actual
	return {
		code = 0,
		stdout = " /nix/store/jdk17/lib/openjdk\n",
	}
end

assert_eq(
	project_env.read_env(source, "JDK17_HOME", "/nix/store/direnv/bin/direnv", successful_run),
	"/nix/store/jdk17/lib/openjdk",
	"project environment value"
)
assert_eq(command, {
	"/nix/store/direnv/bin/direnv",
	"exec",
	android,
	"printenv",
	"JDK17_HOME",
}, "project environment command")
assert_eq(
	project_env.read_env(source, "MISSING", "/nix/store/direnv/bin/direnv", function()
		return { code = 1, stdout = "" }
	end),
	nil,
	"missing project environment value"
)

local config = {
	root_dir = source,
	settings = {
		java = {
			format = { enabled = true },
		},
	},
}
project_env.before_init_env_setting("JDK17_HOME", { "java", "import", "gradle", "java", "home" }, {
	direnv = "/nix/store/direnv/bin/direnv",
	run = successful_run,
})(nil, config)
assert_eq(config.settings, {
	java = {
		format = { enabled = true },
		import = {
			gradle = {
				java = {
					home = "/nix/store/jdk17/lib/openjdk",
				},
			},
		},
	},
}, "nested project environment setting")

local nested = android .. "/ignitionshared"
vim.fn.writefile({ "use flake" }, nested .. "/.envrc")
assert_eq(project_env.find_env_root(source), nested, "nearest envrc")

vim.fn.delete(base, "rf")
print("PASS: LSP project environment selection")
