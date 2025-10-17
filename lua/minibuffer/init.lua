local M = {}

---Initialize
function M.initialize()
  return require("minibuffer.core").initialize()
end

---Open an input session
---Options are forwarded to `M.InputSession.new`.
---@param opts minibuffer.core.InputSessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.input(opts, force)
  local core = require("minibuffer.core")
  return core.start_session(core.InputSession.new(opts or {}), force)
end

---Open a select session
---Options are forwarded to `M.SelectSession.new`.
---@param opts minibuffer.core.SelectSessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.select(opts, force)
  local core = require("minibuffer.core")
  return core.start_session(core.SelectSession.new(opts or {}), force)
end

---Open a display session
---Options are forwarded to `M.DisplaySession.new`.
---@param opts minibuffer.core.DisplaySessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.display(opts, force)
  local core = require("minibuffer.core")
  return core.start_session(core.DisplaySession.new(opts or {}), force)
end

---Resume last interactive minibuffer session
---@param force boolean|nil
---@return boolean started
function M.resume(force)
  return require("minibuffer.core").resume(force)
end

---Return whether a session is currently active
---@return boolean
function M.is_active()
  return require("minibuffer.core").is_active()
end

---Return the currently active session object (or nil)
---@return minibuffer.core.Session|nil
function M.get_active_session()
  return require("minibuffer.core").get_active_session()
end

---Return the window that was active when the session was started (or nil)
---@return integer|nil
function M.get_active_window()
  return require("minibuffer.core").get_active_window()
end

return M
