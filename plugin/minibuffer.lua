if vim.fn.has("nvim-0.12") ~= 1 then
  return
end

if vim.g.loaded_minibuffer then
  return
end
vim.g.loaded_minibuffer = true

local config_ok, _, err = pcall(require, "minibuffer.config")
if not config_ok then
  vim.notify(err or "minibuffer configuration invalid", vim.log.levels.ERROR)
  return
end

local ok, minibuffer = pcall(require, "minibuffer")
if ok then
  minibuffer.initialize()
end
