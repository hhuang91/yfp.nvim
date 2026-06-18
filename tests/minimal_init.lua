-- Minimal init to drive yfp by hand in an isolated Neovim:
--   nvim --clean -u tests/minimal_init.lua
-- then run :YFP
local here = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h:h")
vim.opt.runtimepath:prepend(here)
require("yfp").setup({})
vim.keymap.set("n", "<leader>fy", function()
  require("yfp").open()
end, { desc = "Yank file path (yfp)" })
