-- lua/plugins/treesitter-outline/init.lua
local ok, outline = pcall(require, "treesitter_outline")
if not ok then
  vim.notify("treesitter_outline failed to load", vim.log.levels.ERROR)
  return
end

return outline
