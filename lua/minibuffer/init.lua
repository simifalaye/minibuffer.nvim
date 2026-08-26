---@param session minibuffer.core.Session
---@param force boolean|nil
---@return boolean started
local function start_session(session, force)
  local state = require("minibuffer.internal.state")
  local util = require("minibuffer.internal.util")
  if not state.initialized then
    error("Must call `initialize()` first")
  end
  if force == nil then
    force = false
  end
  if not util.ready() then
    vim.notify("[minibuffer] ext cmd buffer not ready yet.", vim.log.levels.WARN)
    return false
  end
  if not force and state.session and not state.session:overridable() then
    vim.notify("[minibuffer] Session active (use force=true).", vim.log.levels.INFO)
    return false
  end

  local function start()
    state.session = session
    state.pending_render = false
    state.active_window = vim.api.nvim_get_current_win()

    vim.api.nvim_create_autocmd("FocusLost", {
      callback = function()
        vim.schedule(function()
          if state.session then
            state.session:close()
          end
        end)
      end,
    })

    session:pre_start()
    session:render()
    session:post_start()
  end

  if state.session then
    state.session:close(function()
      start()
    end)
  else
    start()
  end

  return true
end

local M = {}

---Initialize plugin
function M.initialize()
  local state = require("minibuffer.internal.state")
  if state.initialized then
    return
  end

  -- TODO: Remove later on
  require("minibuffer.internal.compat").initialize()

  local config = require("minibuffer.config")
  local cmd = require("minibuffer.internal.cmd")

  -- Setup highlights
  local function setup_hl()
    local defs = {
      MinibufferPrompt = { link = "Question" },
      MinibufferSelection = { link = "Visual" },
      MinibufferMultiSelected = { link = "Search" },
      MinibufferSuggestion = { link = "Comment" },
      MinibufferLoading = { link = "Comment" },
    }
    for k, v in pairs(defs) do
      pcall(vim.api.nvim_set_hl, 0, k, v)
    end
  end
  setup_hl()

  -- Setup autocommands
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = state.augroup,
    callback = function()
      setup_hl()
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      if state.session then
        state.session:render()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = state.augroup,
    pattern = { ":", "/", "\\?" },
    desc = "Minibuffer cmd pum",
    callback = function()
      -- Make sure to close any non-cmd sessions
      if state.session then
        state.session:close(function()
          cmd.enable()
        end)
      else
        cmd.enable()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = state.augroup,
    pattern = { ":", "/", "\\?" },
    desc = "Minibuffer cmd pum",
    callback = function()
      cmd.disable()
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = state.augroup,
    callback = function()
      if config.cmd.autotrigger and vim.fn.mode() == "c" then
        vim.fn.wildtrigger()
      end
    end,
  })

  if config.cmd.autotrigger then
    vim.o.wildmode = "noselect,full"
  end

  local cmdline = require("vim._core.ui2.cmdline")
  local original_show = cmdline.cmdline_show
  local original_hide = cmdline.cmdline_hide
  cmdline.cmdline_show = function(content, pos, firstc, prompt, indent, level, hl_id)
    original_show(content, pos, firstc, prompt, indent, level, hl_id)
    -- Set cmdheight after ui2s layout operations to ensure we override it
    if config.cmd.enabled then
      cmd.update_cmdheight()
    end
  end
  cmdline.cmdline_hide = function(level, abort)
    original_hide(level, abort)
    -- Run any final cleanup code after ui2 has finished it's layout operations
    cmd.cleanup()
  end

  -- Wrap win config functions to detect buffers destined for the minibuffer
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_open_win = function(buf, enter, opts)
    if opts.use_minibuffer or opts.relative == "minibuffer" then
      ---@diagnostic disable-next-line: inject-field
      opts.use_minibuffer = nil
      local s = require("minibuffer.sessions.scratch").new({
        win_config = opts,
        buf = buf,
        enter = enter,
      })
      if not start_session(s, false) then
        return 0
      end
      return s:get_win()
    end
    return state.default_nvim_open_win(buf, enter, opts)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_win_set_config = function(win, opts)
    if state.session and state.session:type() == "scratch" then
      local s = state.session
      ---@cast s minibuffer.core.ScratchSession
      if s:get_win() == win then
        ---@diagnostic disable-next-line: inject-field
        opts.use_minibuffer = nil
        s:set_win_config(opts)
        return
      end
    end
    return state.default_nvim_win_set_config(win, opts)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_win_close = function(win, force)
    if state.session and state.session:type() == "scratch" then
      local s = state.session
      ---@cast s minibuffer.core.ScratchSession
      if s:get_win() == win then
        s:close()
      end
    end
    return state.default_nvim_win_close(win, force)
  end

  state.initialized = true
end

---Open an input session
---Options are forwarded to `M.InputSession.new`.
---@param opts minibuffer.core.InputSessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.input(opts, force)
  return start_session(require("minibuffer.sessions.input").new(opts or {}), force)
end

---Open a select session
---Options are forwarded to `M.SelectSession.new`.
---@param opts minibuffer.core.SelectSessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.select(opts, force)
  return start_session(require("minibuffer.sessions.select").new(opts or {}), force)
end

---Open a display session
---Options are forwarded to `M.DisplaySession.new`.
---@param opts minibuffer.core.DisplaySessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.display(opts, force)
  return start_session(require("minibuffer.sessions.display").new(opts or {}), force)
end

---Open a scratch session
---Options are forwarded to `M.ScratchSession.new`.
---@param opts minibuffer.core.ScratchSessionOpts|nil
---@param force boolean|nil
---@return boolean started
function M.scratch(opts, force)
  return start_session(require("minibuffer.sessions.scratch").new(opts or {}), force)
end

---Resume last interactive minibuffer session
---@param force boolean|nil
---@return boolean started
function M.resume(force)
  local state = require("minibuffer.internal.state")
  if not state.prev_session then
    vim.notify("[minibuffer] No session available to resume.", vim.log.levels.WARN)
    return false
  end
  return start_session(state.prev_session, force)
end

---Return whether a session is currently active
---@return boolean
function M.is_active()
  local state = require("minibuffer.internal.state")
  return state.session ~= nil
end

---Return the currently active session object (or nil)
---@return minibuffer.core.Session|nil
function M.get_active_session()
  local state = require("minibuffer.internal.state")
  return state.session
end

---Return the window that was active when the session was started (or nil)
---@return integer|nil
function M.get_active_window()
  local state = require("minibuffer.internal.state")
  return state.active_window
end

return M
