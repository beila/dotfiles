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

local markers = {
	{ "mvnw", "gradlew", "settings.gradle", ".git" },
	{ ".git" },
	"pom.xml",
}
local java_markers = project_env.equal_root_markers(markers, { ".git" })
assert_eq(java_markers, {
	{
		"mvnw",
		"gradlew",
		"settings.gradle",
		"pom.xml",
	},
}, "equal-priority workspace root markers")
assert_eq(markers, {
	{ "mvnw", "gradlew", "settings.gradle", ".git" },
	{ ".git" },
	"pom.xml",
}, "workspace root marker source remains unchanged")

vim.fn.writefile({}, repo .. "/gradlew")
vim.fn.writefile({}, android .. "/pom.xml")
assert_eq(vim.fs.root(source, markers), repo, "priority groups select outer wrapper")
assert_eq(vim.fs.root(source, java_markers), android, "equal-priority markers select nearest nested project")

local selected_root
local selected_source
local selected_markers
project_env.workspace_root(java_markers, function(actual_source, actual_markers)
	selected_source = actual_source
	selected_markers = actual_markers
	return android
end)(source, function(root_dir)
	selected_root = root_dir
end)
assert_eq(selected_source, source, "workspace root source")
assert_eq(selected_markers, java_markers, "workspace root markers")
assert_eq(selected_root, android, "workspace root callback")

local git_only_source = base .. "/git-only/src/main/java"
vim.fn.mkdir(git_only_source, "p")
vim.fn.mkdir(base .. "/git-only/.git", "p")
local git_only_callback_called = false
project_env.workspace_root(java_markers)(git_only_source, function()
	git_only_callback_called = true
end)
assert_eq(git_only_callback_called, false, "git-only workspace skips activation")

local rootless_callback_called = false
project_env.workspace_root(java_markers, function()
	return nil
end)(source, function()
	rootless_callback_called = true
end)
assert_eq(rootless_callback_called, false, "rootless workspace skips activation")

local executable = "/nix/store/jdtls/bin/jdtls"
local direnv = "/nix/store/direnv/bin/direnv"
local launcher = "/nix/store/launcher/bin/lsp-project-env-launcher"
assert_eq(project_env.find_env_root(source), nil, "project without envrc")
assert_eq(
	project_env.resolve_command(executable, source, direnv, launcher),
	{ executable },
	"project without envrc fallback"
)

vim.fn.writefile({
	"pushd ../../.. >/dev/null",
	"use flake .#android",
	"popd >/dev/null",
}, android .. "/.envrc")
assert_eq(project_env.find_env_root(source), android, "Android env root")

assert_eq(project_env.resolve_command(executable, source, direnv, launcher, { timeout = "1.25s" }), {
	launcher,
	"1.25s",
	direnv,
	android,
	executable,
}, "project environment launcher command")
assert_eq(project_env.resolve_command(executable, source, "", launcher), { executable }, "missing direnv fallback")
assert_eq(project_env.resolve_command(executable, source, direnv, ""), { executable }, "missing launcher fallback")

local nested = android .. "/ignitionshared"
vim.fn.writefile({ "use flake" }, nested .. "/.envrc")
assert_eq(project_env.find_env_root(source), nested, "nearest envrc")

local started_command
local started_options
local wrapped = project_env.wrap("jdtls", {
	exepath = function(name)
		local paths = {
			jdtls = executable,
			direnv = direnv,
			["lsp-project-env-launcher"] = launcher,
		}
		return paths[name] or ""
	end,
	start = function(command, _, options)
		started_command = command
		started_options = options
		return "rpc"
	end,
})
assert_eq(
	wrapped({}, {
		root_dir = source,
		cmd_env = { TEST = "1" },
		detached = true,
	}),
	"rpc",
	"wrapped RPC result"
)
assert_eq(started_command, {
	launcher,
	"30s",
	direnv,
	nested,
	executable,
}, "wrapped launcher command")
assert_eq(started_options, {
	cwd = source,
	env = { TEST = "1" },
	detached = true,
}, "wrapped RPC options")

vim.fn.delete(base, "rf")
print("PASS: LSP project environment selection")
