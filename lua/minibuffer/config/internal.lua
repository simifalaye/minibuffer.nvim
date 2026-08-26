---@class minibuffer.internal_config.cmd
---@field enabled boolean
---@field autotrigger boolean
---@field dynamic_height boolean
---@field max_height integer

---@class minibuffer.internal_config
---@field dynamic_window_resize boolean
---@field cmd minibuffer.internal_config.cmd

---@type minibuffer.internal_config
local default_config = {
  dynamic_window_resize = true,
  cmd = {
    enabled = true,
    autotrigger = true,
    dynamic_height = false,
    max_height = 15,
  },
}

---@param value minibuffer.config_source
---@return minibuffer.config
local function get_user_config(value)
  if type(value) == "function" then
    local config = value()
    if config == nil then
      return {}
    end
    return config
  end
  return value or {}
end

local user_config = get_user_config(vim.g.minibuffer)

---@type minibuffer.internal_config
local config = vim.tbl_deep_extend("force", default_config, user_config)

local valid, err = require("minibuffer.config.validate").validate(config)
if not valid then
  error(err)
end

return config
