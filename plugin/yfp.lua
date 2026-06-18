-- yfp — command registration. Kept tiny; everything else lazy-loads on first use.
if vim.g.loaded_yfp then
  return
end
vim.g.loaded_yfp = true

vim.api.nvim_create_user_command("YFP", function(opts)
  local arg = opts.args
  if arg and arg ~= "" then
    require("yfp").open({ cwd = arg })
  else
    require("yfp").open()
  end
end, {
  nargs = "?",
  complete = "dir",
  desc = "yfp: open the floating read-only path browser",
})
