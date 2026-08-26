local M = {}

M.default_nvim_open_win = vim.api.nvim_open_win
M.default_nvim_win_set_config = vim.api.nvim_win_set_config
M.default_nvim_win_close = vim.api.nvim_win_close

---@type boolean
M.initialized = false

---@type boolean
M.pending_render = false

---@type integer|nil
M.active_window = nil

---@type minibuffer.core.Session|nil
M.session = nil

---@type minibuffer.core.Session|nil
M.prev_session = nil

---@type table<integer, minibuffer.util.WindowState>
M.win_states = {}

---@type integer
M.augroup = vim.api.nvim_create_augroup("minibuffer", { clear = true })

---@type integer
M.ns = vim.api.nvim_create_namespace("minibuffer")

--- Wipe state
function M.cleanup()
  M.active_window = nil
  if M.session and M.session.resumable then
    M.prev_session = M.session
  end
  M.session = nil
  M.pending_render = false
  M.active_window = nil
  M.win_sizes = {}
  M.win_views = {}
end

return M
