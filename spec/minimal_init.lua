--- Inspect the contents of an object very quickly
--- ex. P({1,2,3})
--- @vararg any
--- @return any
_G.dd = function(...)
  local objects = {}
  local v
  for i = 1, select("#", ...) do
    v = select(i, ...)
    table.insert(objects, vim.inspect(v))
  end
  print(table.concat(objects, "\n"))
  return ...
end

local _PLUGINS = {}

local cloned = false
for url, directory in pairs(_PLUGINS) do
  if vim.fn.isdirectory(directory) ~= 1 then
    print(string.format('Cloning "%s" plug-in to "%s" path.', url, directory))
    vim.fn.system({ "git", "clone", url, directory })
    cloned = true
  end

  vim.opt.rtp:append(directory)
end
if cloned then
  print("Finished cloning.")
end

vim.opt.rtp:append(".")

-- Disable auto plugin loading and handle in unit tests
vim.g.loaded_minibuffer = true

vim.cmd("runtime plugin/minibuffer.lua")
