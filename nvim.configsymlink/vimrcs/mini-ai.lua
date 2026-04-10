local spec_treesitter = require('mini.ai').gen_spec.treesitter

require('mini.ai').setup {
  n_lines = 500,
  custom_textobjects = {
    -- treesitter-powered: function definition and class (language-aware)
    F = spec_treesitter({ a = '@function.outer', i = '@function.inner' }),
    c = spec_treesitter({ a = '@class.outer', i = '@class.inner' }),
    -- keep builtin mini.ai: f (function call), a (argument), b (bracket), q (quote), t (tag), ? (prompt)
  },
}
