---@mod minibuffer.sessions.scratch ScratchSession
---@brief [[
---Start a scratch minibuffer session which just holds a window inside of the minibuffer area
---@brief ]]

local config = require("minibuffer.config")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")

---@class minibuffer.core.ScratchSession : minibuffer.core.Session
---@field buf integer
---@field win_config vim.api.keyset.win_config
---@field enter boolean
---@field _win integer
local ScratchSession = {}
ScratchSession.__index = ScratchSession
ScratchSession = ScratchSession

---@class minibuffer.core.ScratchSessionOpts
---The buffer for the window to display
---@field buf integer
---The window config to use
---@field win_config vim.api.keyset.win_config
---Whether to enter the window upon creation
---@field enter boolean

--- Create new ScratchSession
---@param opts minibuffer.core.ScratchSessionOpts|nil
---@return minibuffer.core.ScratchSession
function ScratchSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    buf = opts.buf,
    win_config = opts.win_config,
    enter = opts.enter,

    _closed = true,
    _win = -1,
  }, ScratchSession)

  return self
end

--- Get the type of a session
---@return minibuffer.core.SessionType
function ScratchSession:type()
  return "scratch"
end

--- Check if a session is overridable
---@return boolean
function ScratchSession:overridable()
  return true
end

--- Returns whether this session can be resumed
---@return boolean
function ScratchSession:resumable()
  return false
end

--- Session setup
function ScratchSession:pre_start()
  local cmd_win = util.get_cmd_win()
  if not cmd_win then
    return
  end

  self._closed = false
  state.win_states = util.get_window_states()

  util.wipe_cmd_buffer()
end

--- Render session to the screen
function ScratchSession:render()
  if self._closed then
    return
  end

  local cmd_win = util.get_cmd_win()
  if not cmd_win then
    return
  end

  if self._win == -1 or not vim.api.nvim_win_is_valid(self._win) then
    local cfg = self.win_config
    cfg = vim.tbl_deep_extend("force", cfg, {
      anchor = "SW",
      relative = "editor",
      row = vim.o.lines,
      col = 0,
      width = vim.o.columns,
      win = cmd_win,
      zindex = vim.api.nvim_win_get_config(cmd_win).zindex + 1,
    })
    self._win = state.default_nvim_open_win(self.buf, self.enter, cfg)
    pcall(vim.api.nvim_win_set_var, self._win, "minibuffer", true)

    local augroup = vim.api.nvim_create_augroup(
      "minibuffer-win-" .. tostring(self._win),
      { clear = true }
    )
    vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = tostring(self._win),
      callback = function()
        self:close()
      end,
    })
  end

  local cfg = vim.api.nvim_win_get_config(self._win)

  local additional_height = 0
  if type(cfg.border) == "table" then
    if cfg.border[2] ~= "" then
      additional_height = additional_height + 1
    end
    if cfg.border[6] ~= "" then
      additional_height = additional_height + 1
    end
  elseif type(cfg.border) == "string" and cfg.border ~= "none" then
    additional_height = additional_height + 2
  end

  util.set_cmdheight(
    state.win_states,
    config.dynamic_window_resize,
    cfg.height + additional_height
  )

  vim.api.nvim__redraw({ flush = true, cursor = true })
end

--- After first render
function ScratchSession:post_start() end

--- Cancel session
function ScratchSession:cancel()
  if self._closed then
    return
  end

  self:close()
end

--- Close session
---@param done fun()? callback when close is completed
function ScratchSession:close(done)
  if self._closed then
    return
  end
  self._closed = true

  if vim.api.nvim_win_is_valid(self._win) then
    pcall(vim.api.nvim_win_close, self._win, true)
  end
  self._win = -1

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

  if done then
    vim.schedule(function()
      done()
    end)
  end
end

--- Set the window config after it has already been created
---@param c vim.api.keyset.win_config
function ScratchSession:set_win_config(c)
  if self._closed then
    return false
  end

  local cmd_win = util.get_cmd_win()
  if not cmd_win or not vim.api.nvim_win_is_valid(self._win) then
    return
  end

  local cfg = vim.tbl_deep_extend("force", c, {
    anchor = "SW",
    relative = "editor",
    row = vim.o.lines,
    col = 0,
    width = vim.o.columns,
    win = cmd_win,
    zindex = vim.api.nvim_win_get_config(cmd_win).zindex + 1,
  })
  state.default_nvim_win_set_config(self._win, cfg)

  self:render()
end

--- Return the win id
---@return integer
function ScratchSession:get_win()
  return self._win
end

return ScratchSession
