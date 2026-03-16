require 'nvim-treesitter.configs'.setup {
    ensure_installed = {
        -- languages
        "awk", "bash", "c", "cmake", "cpp", "css", "csv", "diff", "dockerfile",
        "dot", "doxygen", "git_config", "git_rebase", "gitattributes", "gitcommit",
        "gitignore", "glsl", "gnuplot", "groovy", "haskell", "html", "htmldjango",
        "idl", "java", "javascript", "jinja", "json", "json5", "jsonc", "just",
        "kotlin", "lua", "make", "markdown", "nim", "ninja", "nix", "passwd",
        "perl", "proto", "python", "rst", "rust", "sql", "ssh_config", "toml",
        "typescript", "udev", "vim", "vimdoc", "xml", "yaml",
        -- injected/inline (not auto-installed)
        "angular", "asm", "coffeescript", "comment", "fish", "glimmer", "graphql",
        "haskell_persistent", "jinja_inline", "jsdoc", "latex", "luadoc", "luap",
        "markdown_inline", "nim_format_string", "pod", "printf", "promql", "query",
        "re2c", "readline", "regex", "ruby", "slint", "styled",
    },
    auto_install = true,
    highlight = { enable = true, },
    indent = { enable = true, },
}
