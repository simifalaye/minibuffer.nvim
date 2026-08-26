---@class minibuffer.config.cmd
---@field enabled? boolean
---@field autotrigger? boolean
---@field dynamic_height? boolean
---@field max_height? integer

---@class minibuffer.config
---@field dynamic_window_resize? boolean
---@field cmd? minibuffer.config.cmd

---@alias minibuffer.config_source minibuffer.config|fun():minibuffer.config|nil

---@type minibuffer.config_source
vim.g.minibuffer = vim.g.minibuffer
