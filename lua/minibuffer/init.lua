---@param session minibuffer.core.Session
---@param force boolean|nil
---@return boolean started
local function start_session(session, force)
  local state = require("minibuffer.state")
  local util = require("minibuffer.util")
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
  if state.session then
    state.session:close()
  end

  state.session = session
  state.pending_render = false
  state.active_window = vim.api.nvim_get_current_win()

  session:pre_start()
  session:render()
  session:post_start()

  return true
end

local M = {}

---Initialize plugin
function M.initialize()
  local state = require("minibuffer.state")
  if state.initialized then
    return
  end

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
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = state.augroup,
    callback = function()
      setup_hl()
    end,
  })

  -- Re-render on resize
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      if state.session then
        state.session:render()
      end
    end,
  })

  local config = require("minibuffer.config")
  local cmdline = require("vim._core.ui2.cmdline")
  local original_show = cmdline.cmdline_show
  local original_hide = cmdline.cmdline_hide
  local cmd_session ---@type minibuffer.core.CmdSession?
  local save_win_sizes
  local save_win_views

  local cmdbuff, prev_pos, prev_cmdbuff
  cmdline.cmdline_show = function(content, pos, firstc, prompt, indent, level, hl_id)
    local conf = config.get()

    -- Make sure to close any non-cmd sessions
    if state.session and state.session ~= cmd_session then
      state.session:close()
    end

    local lines = {} ---@type string[]
    for line in (prompt .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = vim.fn.strtrans(line)
    end

    cmdbuff = ""
    for _, chunk in ipairs(content) do
      cmdbuff = cmdbuff .. chunk[2]
    end
    lines[#lines] = ("%s%s "):format(lines[#lines], vim.fn.strtrans(cmdbuff))

    if cmdbuff == prev_cmdbuff and pos == prev_pos then
      return
    end
    prev_cmdbuff, prev_pos = cmdbuff, pos

    -- We need to save win info before ui2 cmdline code has run
    if conf.cmd.enabled and not cmd_session then
      local util = require("minibuffer.util")
      save_win_sizes = util.get_window_sizes()
      save_win_views = util.get_win_views()
    end

    -- ui2 establishes the command-line buffer and its base height. Render the
    -- suggestion UI afterwards so our cmdheight is the final value.
    original_show(content, pos, firstc, prompt, indent, level, hl_id)
    if not conf.cmd.enabled then
      return
    end

    if not cmd_session then
      local session = require("minibuffer.sessions.cmd").new({
        firstc = firstc,
        initial_input = cmdbuff,
        initial_cursor_pos = pos,
        allow_shrink = conf.cmd.dynamic_height,
        max_height = conf.cmd.max_height,
        win_sizes = save_win_sizes,
      })
      if not start_session(session, true) then
        return
      end
      cmd_session = session
      return
    end

    cmd_session.input = cmdbuff
    cmd_session.cursor_pos = pos
    cmd_session:refresh_suggestions()
    if cmd_session and state.session == cmd_session and not cmd_session.closed then
      cmd_session:render()
    end
  end
  cmdline.cmdline_hide = function(level, abort)
    cmdbuff, prev_cmdbuff, prev_pos = nil, nil, nil
    if cmd_session then
      cmd_session:close()
    end

    -- Leave ui2's hide as the final layout operation.
    original_hide(level, abort)

    if cmd_session then
      -- We need to restore win sizes after ui2 cmdline code has ran
      local util = require("minibuffer.util")
      if save_win_sizes then
        util.restore_window_sizes(save_win_sizes)
      end
      if save_win_views then
        util.restore_win_views(save_win_views)
      end
      cmd_session = nil
    end
  end

  -- Wrap win config functions to detect buffers destined for the minibuffer
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_open_win = function(buf, enter, opts)
    if opts.use_minibuffer then
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
  local state = require("minibuffer.state")
  if not state.prev_session then
    vim.notify("[minibuffer] No session available to resume.", vim.log.levels.WARN)
    return false
  end
  return start_session(state.prev_session, force)
end

---Return whether a session is currently active
---@return boolean
function M.is_active()
  local state = require("minibuffer.state")
  return state.session ~= nil
end

---Return the currently active session object (or nil)
---@return minibuffer.core.Session|nil
function M.get_active_session()
  local state = require("minibuffer.state")
  return state.session
end

---Return the window that was active when the session was started (or nil)
---@return integer|nil
function M.get_active_window()
  local state = require("minibuffer.state")
  return state.active_window
end

return M
