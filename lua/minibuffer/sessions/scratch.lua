local state = require("minibuffer.state")
local util = require("minibuffer.util")
local ext = util.get_ext()

---@class minibuffer.core.ScratchSession : minibuffer.core.Session
---@field buf integer
---@field win_config vim.api.keyset.win_config
---@field enter boolean
---@field _win integer
local ScratchSession = {}
ScratchSession.__index = ScratchSession
ScratchSession = ScratchSession

---@class minibuffer.core.ScratchSessionOpts
---@field buf integer
---@field win_config vim.api.keyset.win_config
---@field enter boolean

---@param opts minibuffer.core.ScratchSessionOpts|nil
---@return minibuffer.core.ScratchSession
function ScratchSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    closed = false,
    resumable = false,
    buf = opts.buf,
    win_config = opts.win_config,
    enter = opts.enter,
  }, ScratchSession)
  self._win = -1

  return self
end

---@return minibuffer.core.SessionType
function ScratchSession:type()
  return "scratch"
end

---@return boolean
function ScratchSession:overridable()
  return true
end

function ScratchSession:pre_start()
  local cmd_win = util.get_cmd_win()
  if not cmd_win then
    return
  end

  self.closed = false
  state.win_sizes = util.get_window_sizes()
  state.win_views = util.get_win_views()

  util.wipe_cmd_buffer()
  util.enable_cmd_buffer_ts(false)
end

function ScratchSession:render()
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

  util.set_win_height(cmd_win, cfg.height + additional_height, true)
  util.resize_windows_for_cmdheight(state.win_sizes, cfg.height - ext.cmdheight)
  vim.cmd.redraw()
end

function ScratchSession:post_start() end

function ScratchSession:cancel()
  self:close()
end

function ScratchSession:close()
  if self.closed then
    return
  end
  self.closed = true

  local function cleanup()
    if vim.api.nvim_win_is_valid(self._win) then
      pcall(vim.api.nvim_win_close, self._win, true)
    end
    self._win = -1

    local win = util.get_cmd_win()
    if not win then
      return
    end

    util.wipe_cmd_buffer()
    util.set_win_height(win, ext.cmdheight, true)
    if state.active_window and vim.api.nvim_win_is_valid(state.active_window) then
      pcall(vim.api.nvim_set_current_win, state.active_window)
    end
    util.restore_window_sizes(state.win_sizes)
    util.restore_win_views(state.win_views)
  end

  cleanup()
  state.cleanup()
end

---@param config vim.api.keyset.win_config
function ScratchSession:set_win_config(config)
  if self.closed then
    return false
  end

  local cmd_win = util.get_cmd_win()
  if not cmd_win or not vim.api.nvim_win_is_valid(self._win) then
    return
  end

  local cfg = vim.tbl_deep_extend("force", config, {
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

function ScratchSession:get_win()
  return self._win
end

return ScratchSession
