-- GLSL/OpenGL: LSP
-- Tools installed via nix in nvim.nix: glsl_analyzer
-- Formatter: clang-format (clang-tools, installed for c/c++ in nvim.nix)

require('lspconfig').glsl_analyzer.setup({})
