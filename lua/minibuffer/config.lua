local M = {}

---@class minibuffer.config

---@class minibuffer.config.State
local state = {
  ---@type minibuffer.config | nil
  config = nil,
}

local function init()
  local config = vim.g.minibuffer or {}
  local default_config = {}

  local merged_config = vim.tbl_deep_extend("force", default_config, config)

  state.config = merged_config
end

--- Configure the minibuffer
--- @param config minibuffer.config Configuration options
function M.configure(config)
  vim.g.minibuffer = config
end

--- @return minibuffer.config the minibuffer configuration
function M.get()
  if not state.config then
    init()
  end
  return state.config
end

return M
