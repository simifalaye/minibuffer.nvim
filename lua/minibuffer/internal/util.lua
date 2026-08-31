local ext = require("vim._core.ui2")
if not ext then
  error(
    "Failed to load vim._core.ui2."
      .. "Make sure you are running neovim 0.12+ "
      .. "with ui2 enabled (require'vim._core.ui2'.enable({}))"
  )
end

---@return integer[]
local function get_resizable_windows()
  local resizable = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    -- Ignore floating windows
    if not cfg.relative or cfg.relative == "" or cfg.relative == "minibuffer" then
      resizable[#resizable + 1] = win
    end
  end
  return resizable
end

---@param states table<integer, minibuffer.util.WindowState>
---@param cmdheight integer
local function resize_windows_for_cmdheight(states, cmdheight)
  local delta = cmdheight - ext.cmdheight
  if delta == 0 then
    return
  end

  local function subtree_height(node)
    if node[1] == "leaf" then
      return states[node[2]] and states[node[2]].height or 0
    end

    local total = 0
    if node[1] == "col" then
      for _, child in ipairs(node[2]) do
        total = total + subtree_height(child)
      end
    else -- row
      for _, child in ipairs(node[2]) do
        total = math.max(total, subtree_height(child))
      end
    end
    return total
  end

  local layout = vim.fn.winlayout()
  local root_height = subtree_height(layout)
  local new_root_height = math.max(1, root_height - delta)

  -- Split an integer amount proportionally.
  -- Example:
  --   total = 17
  --   weights = { 10, 10, 10 }
  -- Gives { 6, 6, 5 }
  --
  -- This guarantees that:
  --     sum(result) == total
  -- while keeping the result as close as possible to the exact proportions.
  local function proportional_integer_split(total, weights)
    local r = {}
    local remainders = {}
    local weight_sum = 0

    for _, weight in ipairs(weights) do
      weight_sum = weight_sum + weight
    end

    if weight_sum == 0 then
      for i = 1, #weights do
        r[i] = 0
      end
      return r
    end

    local assigned = 0
    for i, weight in ipairs(weights) do
      local numerator = total * weight
      local value = math.floor(numerator / weight_sum)
      r[i] = value
      assigned = assigned + value
      remainders[i] = numerator % weight_sum
    end

    -- Distribute the leftover rows to the children with the largest fractional remainders
    local remaining = total - assigned
    while remaining > 0 do
      local best = 1
      for i = 2, #weights do
        if remainders[i] > remainders[best] then
          best = i
        end
      end
      r[best] = r[best] + 1
      remainders[best] = -1
      remaining = remaining - 1
    end

    return r
  end

  -- Recursively assign target heights.
  -- target_height is the height that this entire subtree must occupy.
  local function assign(node, target_height)
    local kind = node[1]

    if kind == "leaf" then
      local w = node[2]
      local state = states[w]
      if not state then
        return
      end

      -- Set the window height
      vim.api.nvim_win_set_height(w, target_height)

      -- Set the top line based on the amount we shrunk the window by
      local view = vim.deepcopy(state.view)
      local topline = math.min(view.topline + (state.height - target_height), view.lnum)
      view.topline = topline
      vim.api.nvim_win_call(w, function()
        vim.fn.winrestview(view)
      end)
      return
    end

    local children = node[2]
    if #children == 0 then
      return
    end

    if kind == "row" then
      -- Side-by-side: The children have exactly the same height.
      for _, child in ipairs(children) do
        assign(child, target_height)
      end
    else -- col
      -- Stacked: The children have to divide the available height.
      local weights = {}
      for _, child in ipairs(children) do
        weights[#weights + 1] = subtree_height(child)
      end

      local child_heights = proportional_integer_split(target_height, weights)
      for i, child in ipairs(children) do
        assign(child, child_heights[i])
      end
    end
  end

  assign(layout, new_root_height)
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

function M.enable_buffer_ts(buf, enable)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local parser = assert(vim.treesitter.get_parser(ext.bufs.cmd, "vim", {}))
  local highlighter = vim.treesitter.highlighter.new(parser)
  highlighter.active[ext.bufs.cmd] = enable and highlighter or nil
end

---@param win integer
---@return integer|nil
function M.focus_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local active_win = vim.api.nvim_get_current_win()
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

---@return table<integer, minibuffer.util.WindowState>
function M.get_window_states()
  local states = {}
  for _, win in ipairs(get_resizable_windows()) do
    local view = vim.api.nvim_win_call(win, function()
      return vim.fn.winsaveview()
    end)
    states[win] = {
      height = vim.api.nvim_win_get_height(win),
      buf = vim.api.nvim_win_get_buf(win),
      view = view,
    }
  end
  return states
end

---@param states table<integer, minibuffer.util.WindowState>
function M.restore_window_states(states)
  for win, state in pairs(states) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.buf then
      vim.api.nvim_win_set_height(win, state.height)
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview(state.view)
      end)
    end
  end
end

---@param win integer|nil
---@param height integer
function M.set_win_height(win, height)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if vim.api.nvim_win_get_config(win).height == height then
    return
  end
  if height == 0 then
    vim.api.nvim_win_set_config(win, { hide = true, height = 1 })
  elseif vim.api.nvim_win_get_height(win) ~= height then
    vim.api.nvim_win_set_config(win, { hide = false, height = height })
  end
end

---@param states table<integer, minibuffer.util.WindowState>
---@param resize_windows boolean
---@param height integer|nil If nil the reset to ext.cmdheight
function M.set_cmdheight(states, resize_windows, height)
  local win = M.get_cmd_win()
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if vim.api.nvim_win_get_config(win).height == height then
    return
  end

  height = height or ext.cmdheight
  if height == 0 then
    vim.api.nvim_win_set_config(win, { hide = true, height = 1 })
  elseif vim.api.nvim_win_get_height(win) ~= height then
    vim.api.nvim_win_set_config(win, { hide = false, height = height })
  end

  if vim.api.nvim_get_option_value("cmdheight", { scope = "global" }) ~= height then
    -- Avoid moving the cursor with 'splitkeep' = "screen", and altering the user
    -- configured value with noautocmd.
    vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
      vim.api.nvim_set_option_value("cmdheight", height, { scope = "global" })
    end)
    ext.msg.set_pos()
  end

  if resize_windows then
    resize_windows_for_cmdheight(states, height)
  end
end

---@param buf integer
---@param ns integer
---@param lines_data minibuffer.util.HighlightLine[]
---@param opts minibuffer.util.WriteLinesOpts|nil
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

---@param conditional fun():boolean
---@param base_opts vim.keymap.set.Opts?
---@return minibuffer.util.Keyset
function M.create_condition_keyset(conditional, base_opts)
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

    vim.keymap.set(
      mode,
      lhs,
      wrapped_rhs,
      vim.tbl_deep_extend("force", base_opts or {}, opts or {})
    )
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
