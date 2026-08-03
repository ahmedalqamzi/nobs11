vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = 'yes'
opt.termguicolors = true
opt.mouse = 'a'
opt.clipboard = 'unnamedplus'
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = 'split'
opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 6
opt.sidescrolloff = 8
opt.updatetime = 250
opt.timeoutlen = 400
opt.undofile = true
opt.swapfile = false
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.wrap = false
opt.completeopt = { 'menuone', 'noselect' }
opt.laststatus = 3

vim.cmd.colorscheme('habamax')
vim.api.nvim_set_hl(0, 'Normal', { fg = '#cdd6f4', bg = '#1e1e2e' })
vim.api.nvim_set_hl(0, 'NormalFloat', { fg = '#cdd6f4', bg = '#181825' })
vim.api.nvim_set_hl(0, 'CursorLine', { bg = '#313244' })
vim.api.nvim_set_hl(0, 'LineNr', { fg = '#6c7086' })
vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#cba6f7', bold = true })
vim.api.nvim_set_hl(0, 'Visual', { bg = '#45475a' })
vim.api.nvim_set_hl(0, 'StatusLine', { fg = '#11111b', bg = '#89b4fa', bold = true })
vim.api.nvim_set_hl(0, 'StatusLineNC', { fg = '#7f849c', bg = '#181825' })

local map = vim.keymap.set
map('n', '<leader>w', '<cmd>write<cr>', { desc = 'Write file' })
map('n', '<leader>q', '<cmd>quit<cr>', { desc = 'Quit window' })
map('n', '<leader>e', '<cmd>Ex<cr>', { desc = 'File explorer' })
map('n', '<leader>h', '<C-w>h', { desc = 'Focus left' })
map('n', '<leader>j', '<C-w>j', { desc = 'Focus down' })
map('n', '<leader>k', '<C-w>k', { desc = 'Focus up' })
map('n', '<leader>l', '<C-w>l', { desc = 'Focus right' })
map('v', '<', '<gv')
map('v', '>', '>gv')
map('n', '<Esc>', '<cmd>nohlsearch<cr>')
map('n', '[b', '<cmd>bprevious<cr>', { desc = 'Previous buffer' })
map('n', ']b', '<cmd>bnext<cr>', { desc = 'Next buffer' })
map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')

vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank()
  end,
})
