---@class minibuffer.cmd.Config
---@field enabled boolean
---@field autotrigger boolean
---@field dynamic_height boolean
---@field max_height integer

---@class minibuffer.Config
---@field dynamic_window_resize boolean
---@field cmd minibuffer.cmd.Config

---@type minibuffer.Config
local default_config = {
  dynamic_window_resize = true,
  cmd = {
    enabled = true,
    autotrigger = true,
    dynamic_height = false,
    max_height = 15,
  },
}

local user_config = type(vim.g.minibuffer) == "function" and vim.g.minibuffer()
  or vim.g.minibuffer
  or {}

---@type minibuffer.Config
local config = vim.tbl_deep_extend("force", default_config, user_config)

local valid, err = require("minibuffer.config.validate").validate(config)
if not valid then
  error(err)
end

return config
