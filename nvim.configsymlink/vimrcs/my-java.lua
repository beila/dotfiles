-- Java: LSP, DAP, linter, formatter
-- Tools installed via nix in nvim.nix:
--   jdt-language-server, google-java-format, checkstyle
-- Tools installed via Mason in mason.lua:
--   java-debug-adapter (not in nixpkgs)

-- LSP: jdtls (jdt-language-server)
local project_env = require("lsp-project-env")
local root_markers = project_env.filter_root_markers(vim.lsp.config.jdtls.root_markers, { ".git" })
local command = project_env.with_root_settings(project_env.wrap("jdtls"), function(root_dir)
	return {
		java = {
			import = {
				gradle = {
					arguments = {
						"-Dorg.gradle.java.installations.paths=" .. vim.fs.joinpath(root_dir, ".direnv/jdk17"),
					},
				},
			},
		},
	}
end)
vim.lsp.config.jdtls = {
	cmd = command,
	root_dir = project_env.workspace_root(root_markers),
}
vim.lsp.enable("jdtls")

-- DAP: java-debug-adapter (Mason-installed)
local dap = require("dap")
dap.configurations.java = {
	{
		name = "Launch Java",
		type = "java",
		request = "launch",
	},
}
