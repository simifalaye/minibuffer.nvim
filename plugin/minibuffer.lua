if vim.fn.has("nvim-0.12") ~= 1 then
  return
end

if vim.g.loaded_minibuffer then
  return
end
vim.g.loaded_minibuffer = true

local ok, minibuffer = pcall(require, "minibuffer")
if ok then
  minibuffer.initialize()
end
