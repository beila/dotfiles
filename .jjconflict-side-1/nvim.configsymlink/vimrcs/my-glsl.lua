-- GLSL/OpenGL: LSP
-- Tools installed via nix in nvim.nix: glsl_analyzer
-- Formatter: clang-format (clang-tools, installed for c/c++ in nvim.nix)

vim.lsp.config.glsl_analyzer = {}
vim.lsp.enable('glsl_analyzer')
