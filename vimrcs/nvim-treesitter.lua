require 'nvim-treesitter.configs'.setup {
    ensure_installed = { "awk", "bash", "c", "cmake", "cpp", "css", "csv", "diff", "dockerfile", "dot", "doxygen", "git_config", "git_rebase", "gitattributes", "gitcommit", "gitignore", "glsl", "gnuplot", "groovy", "haskell", "html", "htmldjango", "idl", "java", "javascript", "jinja", "jsdoc", "json", "json5", "jsonc", "just", "kotlin", "lua", "make", "markdown", "markdown_inline", "nim", "ninja", "nix", "passwd", "perl", "printf", "proto", "python", "regex", "rst", "rust", "sql", "ssh_config", "toml", "typescript", "udev", "vim", "vimdoc", "xml", "yaml" },
    auto_install = true,
    highlight = { enable = true, },
    indent = { enable = true, },
}
