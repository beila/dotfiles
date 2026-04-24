require('todo-comments').setup()
vim.keymap.set('n', ']t', function() require('todo-comments').jump_next() end)
vim.keymap.set('n', '[t', function() require('todo-comments').jump_prev() end)
