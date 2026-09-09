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
assert_eq(
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv", {
		run = function()
			fail("direnv ran without an envrc")
		end,
	}),
	{ "/nix/store/jdtls/bin/jdtls" },
	"project without envrc fallback"
)

vim.fn.writefile({
	"pushd ../../.. >/dev/null",
	"use flake .#android",
	"popd >/dev/null",
}, android .. "/.envrc")
assert_eq(project_env.find_env_root(source), android, "Android env root")

local preflight_command
local preflight_timeout
local function successful_run(command, timeout_ms)
	preflight_command = command
	preflight_timeout = timeout_ms
	return { code = 0, stdout = "", stderr = "" }
end

assert_eq(
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv", {
		run = successful_run,
		timeout_ms = 1234,
	}),
	{
		"/nix/store/direnv/bin/direnv",
		"exec",
		android,
		"/nix/store/jdtls/bin/jdtls",
	},
	"direnv command"
)
assert_eq(preflight_command, {
	"/nix/store/direnv/bin/direnv",
	"exec",
	android,
	"true",
}, "direnv preflight command")
assert_eq(preflight_timeout, 1234, "direnv preflight timeout")

assert_eq(
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, ""),
	{ "/nix/store/jdtls/bin/jdtls" },
	"missing direnv fallback"
)

local failed_command, failed_warning =
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv", {
		run = function()
			return { code = 1, stdout = "", stderr = "not allowed\nmore detail" }
		end,
	})
assert_eq(failed_command, { "/nix/store/jdtls/bin/jdtls" }, "failed direnv command fallback")
assert(failed_warning:find("not allowed", 1, true), "failed direnv warning")

local timeout_command, timeout_warning =
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv", {
		run = function()
			return { code = 124, stdout = "", stderr = "" }
		end,
		timeout_ms = 25,
	})
assert_eq(timeout_command, { "/nix/store/jdtls/bin/jdtls" }, "timed-out direnv command fallback")
assert(timeout_warning:find("timed out after 25 ms", 1, true), "timed-out direnv warning")

local error_command, error_warning =
	project_env.resolve_command("/nix/store/jdtls/bin/jdtls", source, "/nix/store/direnv/bin/direnv", {
		run = function()
			error("runner failed")
		end,
	})
assert_eq(error_command, { "/nix/store/jdtls/bin/jdtls" }, "errored direnv command fallback")
assert(error_warning:find("runner failed", 1, true), "errored direnv warning")

local started_command
local started_options
local notification
local wrapped = project_env.wrap("jdtls", {
	exepath = function(name)
		return "/nix/store/" .. name .. "/bin/" .. name
	end,
	run = function()
		return { code = 1, stdout = "", stderr = "blocked" }
	end,
	notify = function(message, level)
		notification = { message, level }
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
assert_eq(started_command, { "/nix/store/jdtls/bin/jdtls" }, "wrapped fallback command")
assert_eq(started_options, {
	cwd = source,
	env = { TEST = "1" },
	detached = true,
}, "wrapped RPC options")
assert(notification[1]:find("blocked", 1, true), "wrapped failure notification")
assert_eq(notification[2], vim.log.levels.WARN, "wrapped failure notification level")

local nested = android .. "/ignitionshared"
vim.fn.writefile({ "use flake" }, nested .. "/.envrc")
assert_eq(project_env.find_env_root(source), nested, "nearest envrc")

vim.fn.delete(base, "rf")
print("PASS: LSP project environment selection")
