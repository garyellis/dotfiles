vim.g.mapleader = " "

vim.keymap.set("n", "<leader>ff", function()
  require("telescope.builtin").find_files()
end, { desc = "Find files" })

vim.keymap.set("n", "<leader>fg", function()
  require("telescope.builtin").live_grep()
end, { desc = "Live grep" })

vim.keymap.set("n", "<leader>fb", function()
  require("telescope.builtin").buffers()
end, { desc = "Buffers" })

vim.keymap.set("n", "<leader>fh", function()
  require("telescope.builtin").help_tags()
end, { desc = "Help tags" })

-- Horizontal terminal split (bottom)
vim.keymap.set("n", "<leader>t", function()
  vim.cmd("split")
  vim.cmd("terminal zsh")
end, { desc = "Terminal (horizontal)" })

-- Vertical terminal split (right)
vim.keymap.set("n", "<leader>T", function()
  vim.cmd("vsplit")
  vim.cmd("terminal zsh")
end, { desc = "Terminal (vertical)" })

-- toggle inlay typehints
vim.keymap.set("n", "<leader>th", function()
  local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
end, { desc = "Toggle LSP inlay hints" })

-- toggle diagnostics
vim.keymap.set("n", "<leader>td", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local enabled = vim.diagnostic.is_enabled({ bufnr = bufnr })
  vim.diagnostic.enable(not enabled, { bufnr = bufnr })
end, { desc = "Toggle diagnostics (errors/warnings)" })

-- markdown
vim.keymap.set('n', '<leader>md', function()
  if vim.bo.filetype ~= 'markdown' then
    vim.notify('Not a markdown file', vim.log.levels.WARN)
    return
  end

  -- Check if file is saved
  local filepath = vim.fn.expand('%:p')
  if filepath == '' then
    vim.notify('Please save the buffer first', vim.log.levels.WARN)
    return
  end

  -- Check if file has been modified
  if vim.bo.modified then
    vim.notify('File has unsaved changes, saving first...', vim.log.levels.INFO)
    vim.cmd('write')
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  
  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
  })
  
  vim.fn.termopen('glow ' .. vim.fn.shellescape(filepath))
  vim.cmd('startinsert')
end, { desc = 'Preview markdown with glow' })
