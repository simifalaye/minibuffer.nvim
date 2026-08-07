local ext = require("vim._core.ui2")
if not ext then
  error(
    "Failed to load vim._core.ui2. Make sure you are running neovim 0.12+ with ui2 enabled (require'vim._core.ui2'.enable({}))"
  )
end

local M = {}

function M.get_ext()
  return ext
end

---@return integer|nil
function M.get_cmd_win()
  if ext.wins and ext.wins.cmd and vim.api.nvim_win_is_valid(ext.wins.cmd) then
    return ext.wins.cmd
  end
  return nil
end

---@return integer|nil
function M.get_cmd_buf()
  if ext.bufs and ext.bufs.cmd and vim.api.nvim_buf_is_valid(ext.bufs.cmd) then
    return ext.bufs.cmd
  end
  return nil
end

---@return boolean
function M.ready()
  return M.get_cmd_win() ~= nil and M.get_cmd_buf() ~= nil
end

function M.wipe_cmd_buffer()
  local buf = M.get_cmd_buf()
  if not buf then
    return
  end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {})
  pcall(vim.api.nvim_buf_clear_namespace, buf, ext.ns, 0, -1)
end

function M.enable_cmd_buffer_ts(enable)
  local buf = M.get_cmd_buf()
  if not buf then
    return
  end
  local parser = assert(vim.treesitter.get_parser(ext.bufs.cmd, "vim", {}))
  local highlighter = vim.treesitter.highlighter.new(parser)
  highlighter.active[ext.bufs.cmd] = enable and highlighter or nil
end

---@return integer|nil
function M.focus_cmd_win()
  local active_win = vim.api.nvim_get_current_win()
  local win = M.get_cmd_win()
  if not win then
    return nil
  end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.focusable == false then
    cfg.focusable = true
    vim.api.nvim_win_set_config(win, cfg)
  end
  vim.api.nvim_set_current_win(win)
  return active_win
end

---@param kind '"buf"'|'"win"'|'"global"'
---@param optnames string[]
---@return table
function M.save_cmd_opts(kind, optnames)
  local saved = {}
  local opts = {}
  if kind == "buf" then
    local buf = M.get_cmd_buf()
    if not buf then
      return {}
    end
    opts.buf = buf
  elseif kind == "win" then
    local win = M.get_cmd_win()
    if not win then
      return {}
    end
    opts.win = win
  elseif kind == "global" then
    opts.scope = "global"
  else
    error("Invalid option kind: " .. tostring(kind))
  end
  for _, name in ipairs(optnames) do
    saved[name] = vim.api.nvim_get_option_value(name, opts)
  end
  return saved
end

---@param kind '"buf"'|'"win"'|'"global"'
---@param opts table<string, any>
function M.restore_cmd_opts(kind, opts)
  local api_opts = {}
  if kind == "buf" then
    local buf = M.get_cmd_buf()
    if not buf then
      return
    end
    api_opts.buf = buf
  elseif kind == "win" then
    local win = M.get_cmd_win()
    if not win then
      return
    end
    api_opts.win = win
  elseif kind == "global" then
    api_opts.scope = "global"
  else
    error("Invalid option kind: " .. tostring(kind))
  end
  for name, value in pairs(opts) do
    vim.api.nvim_set_option_value(name, value, api_opts)
  end
end

---@return integer[]
function M.get_resizable_windows()
  local resizable = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    if not cfg.relative or cfg.relative == "" then
      resizable[#resizable + 1] = win
    end
  end
  return resizable
end

---@return table<integer, integer>
function M.get_window_sizes()
  local win_sizes = {}
  for _, win in ipairs(M.get_resizable_windows()) do
    win_sizes[win] = vim.api.nvim_win_get_height(win)
  end
  return win_sizes
end

---@param win_sizes table<integer, integer>
---@param extra integer
function M.resize_windows_for_cmdheight(win_sizes, extra)
  local total = 0
  for _, h in pairs(win_sizes) do
    total = total + h
  end
  if total == 0 then
    return
  end
  for win, h in pairs(win_sizes) do
    local new_h = math.max(1, math.floor(h - (h / total) * extra))
    vim.api.nvim_win_set_height(win, new_h)
  end
end

---@param win_sizes table<integer, integer>
function M.restore_window_sizes(win_sizes)
  for win, h in pairs(win_sizes) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, h)
    end
  end
  win_sizes = {}
end

---@return table<integer, { buf: integer, view: vim.fn.winsaveview.ret }>
function M.get_win_views()
  local win_views = {}
  local buf = -1
  local view = nil
  for _, win in ipairs(M.get_resizable_windows()) do
    buf = vim.api.nvim_win_get_buf(win)
    view = vim.api.nvim_win_call(win, function()
      return vim.fn.winsaveview()
    end)
    win_views[win] = { buf = buf, view = view }
  end
  return win_views
end

---@param win_views table<integer, { buf: integer, view: vim.fn.winsaveview.ret }>
function M.restore_win_views(win_views)
  for win, d in pairs(win_views) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == d.buf then
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(d.view)
      end)
    end
  end
end

---@param win integer
---@param height integer
---@param set_cmdheight boolean
function M.set_win_height(win, height, set_cmdheight)
  if height == 0 then
    vim.api.nvim_win_set_config(win, { hide = true, height = 1 })
  elseif vim.api.nvim_win_get_height(win) ~= height then
    vim.api.nvim_win_set_config(win, { hide = false, height = height })
  end
  if set_cmdheight and vim.o.cmdheight ~= height then
    -- Avoid moving the cursor with 'splitkeep' = "screen", and altering the user
    -- configured value with noautocmd.
    vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
      vim.o.cmdheight = height
    end)
    ext.msg.set_pos()
  end
end

---@class minibuffer.core.WriteLinesOpts
---@field start_line integer|nil
---@field replace_existing boolean|nil

---@param buf integer
---@param ns integer
---@param lines_data minibuffer.core.HighlightLine[]
---@param opts minibuffer.core.WriteLinesOpts|nil
function M.write_highlighted_lines(buf, ns, lines_data, opts)
  opts = opts or {}
  local start_line = opts.start_line or 0
  local replace_existing = opts.replace_existing ~= false

  local text_lines = {}
  local highlight_info = {}

  for line_idx, line_chunks in ipairs(lines_data) do
    local line_text = ""
    local line_highlights = {}

    for _, chunk in ipairs(line_chunks) do
      local chunk_text = chunk.text or ""
      local start_col = #line_text
      line_text = line_text .. chunk_text
      local end_col = #line_text
      if chunk.hl then
        line_highlights[#line_highlights + 1] = {
          hl_group = chunk.hl,
          start_col = start_col,
          end_col = end_col,
        }
      end
    end

    text_lines[line_idx] = line_text
    highlight_info[line_idx] = line_highlights
  end

  local end_line = replace_existing and (start_line + #text_lines) or start_line

  if replace_existing then
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {})
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  end

  vim.api.nvim_buf_set_lines(buf, start_line, end_line, false, text_lines)

  for line_idx, line_highlights in ipairs(highlight_info) do
    local actual_line = start_line + line_idx - 1
    for _, hl in ipairs(line_highlights) do
      vim.api.nvim_buf_set_extmark(buf, ns, actual_line, hl.start_col, {
        hl_group = hl.hl_group,
        end_col = hl.end_col,
      })
    end
  end
end

---@alias minibuffer.util.Keyset fun(mode:string|string[], lhs:string, rhs:string|function, opts?:vim.keymap.set.Opts)

---@param conditional fun():boolean
---@return minibuffer.util.Keyset
function M.create_condition_keyset(conditional)
  return function(mode, lhs, rhs, opts)
    opts = opts or {}

    local wrapped_rhs = function() end
    if type(rhs) == "function" then
      wrapped_rhs = function()
        if conditional() then
          rhs()
        end
      end
    elseif type(rhs) == "string" then
      wrapped_rhs = function()
        if conditional() then
          local current_mode = vim.api.nvim_get_mode().mode
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(rhs, true, false, true),
            current_mode,
            true
          )
        end
      end
    end

    vim.keymap.set(mode, lhs, wrapped_rhs, opts)
  end
end

--- Create a debounce wrapper function
---@param ms integer
---@return fun(fn:fun())
function M.make_debounced(ms)
  local timer = vim.uv.new_timer()
  return function(fn)
    if not timer then
      return
    end
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(fn)
    end)
  end
end

return M
