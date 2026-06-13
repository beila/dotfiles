local dap = require('dap')
local dapui = require('dapui')

dapui.setup {
  icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
}

dap.listeners.after.event_initialized['dapui_config'] = dapui.open
dap.listeners.before.event_terminated['dapui_config'] = dapui.close
dap.listeners.before.event_exited['dapui_config'] = dapui.close

vim.keymap.set('n', '<F7>', dapui.toggle, { desc = 'Debug: Toggle UI' })
