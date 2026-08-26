local config = require("minibuffer.config")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")

---@class minibuffer.core.DisplaySession : minibuffer.core.Session
---@field lines minibuffer.util.HighlightLine[]
---@field timeout integer|nil
---@field close_keys string[]
---@field dynamic_height boolean
---@field on_close minibuffer.core.CloseCallback|nil
---@field _timer uv.uv_timer_t|nil
local DisplaySession = {}
DisplaySession.__index = DisplaySession

---@class minibuffer.core.DisplaySessionOpts
---@field lines minibuffer.util.HighlightLine[]
---@field timeout integer|nil
---@field close_keys string[]|nil
---@field dynamic_height boolean|nil
---@field on_close minibuffer.core.CloseCallback|nil

---@param opts minibuffer.core.DisplaySessionOpts|nil
---@return minibuffer.core.DisplaySession
function DisplaySession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    resumable = false,
    lines = opts.lines or {},
    timeout = opts.timeout,
    close_keys = opts.close_keys or { "<F5>" },
    dynamic_height = opts.dynamic_height == true,
    on_close = opts.on_close,

    _closed = false,
    _timer = nil,
  }, DisplaySession)
  return self
end

---@return minibuffer.core.SessionType
function DisplaySession:type()
  return "display"
end

---@return boolean
function DisplaySession:overridable()
  return true
end

function DisplaySession:pre_start()
  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  self._closed = false
  state.win_states = util.get_window_states()

  if self.timeout and self.timeout > 0 then
    local _timer = vim.uv.new_timer()
    self._timer = _timer
    self._timer:start(self.timeout, 0, function()
      vim.schedule(function()
        if state.session == self then
          self:close()
        else
          if _timer then
            pcall(_timer.stop, _timer)
            pcall(_timer.close, _timer)
          end
        end
      end)
    end)
  end

  util.wipe_cmd_buffer()
end

function DisplaySession:render()
  if self._closed then
    return
  end

  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  local lines_data = {}
  for _, line in ipairs(self.lines) do
    lines_data[#lines_data + 1] = line
  end

  util.write_highlighted_lines(buf, state.ns, lines_data)

  local new_height = #lines_data
  if not self.dynamic_height then
    new_height = math.max(vim.api.nvim_win_get_height(win), new_height)
  end
  util.set_cmdheight(state.win_states, config.dynamic_window_resize, new_height + 1)

  vim.api.nvim__redraw({ flush = true, cursor = true })
end

function DisplaySession:post_start()
  if self._closed then
    return
  end

  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  local base = { buf = buf, nowait = true, silent = true, noremap = true }
  for _, k in ipairs(self.close_keys) do
    vim.keymap.set({ "n" }, k, function()
      if state.session == self then
        self:close()
      end
    end, base)
  end
end

function DisplaySession:cancel()
  if self._closed then
    return
  end

  self:close()
end

function DisplaySession:close(done)
  if self._closed then
    return
  end
  self._closed = true

  if self._timer then
    pcall(self._timer.stop, self._timer)
    pcall(self._timer.close, self._timer)
    self._timer = nil
  end

  local win = util.get_cmd_win()
  if not win then
    return
  end

  util.wipe_cmd_buffer()
  util.set_cmdheight(state.win_states, config.dynamic_window_resize)
  if state.active_window and vim.api.nvim_win_is_valid(state.active_window) then
    pcall(vim.api.nvim_set_current_win, state.active_window)
  end
  util.restore_window_states(state.win_states)

  state.cleanup()

  local cb = self.on_close
  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
  if done then
    vim.schedule(function()
      done()
    end)
  end
end

---@param lines minibuffer.core.HighlightLine[]
---@return boolean
function DisplaySession:update_lines(lines)
  if self._closed then
    return false
  end

  self.lines = lines
  self:render()
  return true
end

return DisplaySession
