local PREFIX = "minibuffer.examples."
local TARGET_PREFIX = "minibuffer.builtin."

local installed = false

local function deprecate(old, new)
  vim.notify(("%s has been moved to %s"):format(old, new), vim.log.levels.WARN, {
    title = "minibuffer",
  })
end

local function install_examples_compat()
  local preload = package.preload

  if installed then
    return
  end
  installed = true

  local mt = getmetatable(preload) or {}
  local previous_index = mt.__index

  mt.__index = function(tbl, name)
    if previous_index then
      local loader
      if type(previous_index) == "function" then
        loader = previous_index(tbl, name)
      else
        loader = previous_index[name]
      end
      if loader ~= nil then
        return loader
      end
    end

    if name:sub(1, #PREFIX) ~= PREFIX then
      return nil
    end

    local target = TARGET_PREFIX .. name:sub(#PREFIX + 1)
    local loader = function()
      deprecate(name, target)
      return require(target)
    end

    rawset(tbl, name, loader)

    return loader
  end

  setmetatable(preload, mt)
end

local M = {}

function M.initialize()
  install_examples_compat()
end

return M
