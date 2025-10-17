local ext = require("vim._extui.shared")
if not ext then
  error(
    "Failed to load vim._extui. Make sure you are running neovim 0.12+ with extui enabled (require'vim._extui'.enable({}))"
  )
end

local M = {}

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

---@param kind '"buf"'|'"win"'
---@param optnames string[]
---@return table
function M.save_cmd_opts(kind, optnames)
  local saved = {}
  local scope = {}
  if kind == "buf" then
    local buf = M.get_cmd_buf()
    if not buf then
      return {}
    end
    scope.buf = buf
  elseif kind == "win" then
    local win = M.get_cmd_win()
    if not win then
      return {}
    end
    scope.win = win
  end
  for _, name in ipairs(optnames) do
    saved[name] = vim.api.nvim_get_option_value(name, scope)
  end
  return saved
end

---@param kind '"buf"'|'"win"'
---@param opts table<string, any>
function M.restore_cmd_opts(kind, opts)
  local scope = {}
  if kind == "buf" then
    local buf = M.get_cmd_buf()
    if not buf then
      return
    end
    scope.buf = buf
  elseif kind == "win" then
    local win = M.get_cmd_win()
    if not win then
      return
    end
    scope.win = win
  end
  for name, value in pairs(opts) do
    vim.api.nvim_set_option_value(name, value, scope)
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
    if height ~= 0 then
      vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
        vim.o.cmdheight = height
      end)
    else
      vim.o.cmdheight = 0
    end
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
  local timer
  return function(fn)
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.uv.new_timer()
    if not timer then
      return
    end
    timer:start(ms, 0, function()
      timer:stop()
      timer:close()
      timer = nil
      vim.schedule(fn)
    end)
  end
end

-- --- Simple fuzzy match scoring function
-- ---@param str string
-- ---@param query string
-- ---@return integer? score
-- function M.fuzzy_score(str, query)
--   if query == "" then
--     return 0
--   end
--   if str == query then
--     return math.huge
--   end -- perfect match
--
--   local lower_str, lower_query = str:lower(), query:lower()
--   local score, consecutive, last_match = 0, 0, 0
--
--   for i = 1, #lower_query do
--     local qc = lower_query:sub(i, i)
--     local found = lower_str:find(qc, last_match + 1, true)
--     if not found then
--       return nil -- query char not found in order
--     end
--
--     -- base score
--     local char_score = 1
--
--     -- bonus: consecutive characters
--     if found == last_match + 1 then
--       consecutive = consecutive + 1
--       char_score = char_score + (consecutive * 2)
--     else
--       consecutive = 0
--     end
--
--     -- bonus: start of string or after separator
--     if found == 1 or str:sub(found - 1, found - 1):match("[%s%p_]") then
--       char_score = char_score + 3
--     end
--
--     -- bonus: case-sensitive match
--     if str:sub(found, found) == query:sub(i, i) then
--       char_score = char_score + 1
--     end
--
--     -- penalty: distance from last match
--     if last_match > 0 then
--       local gap = found - last_match - 1
--       if gap > 0 then
--         char_score = char_score - math.min(gap, 3) -- small penalty
--       end
--     end
--
--     score = score + char_score
--     last_match = found
--   end
--
--   return score
-- end
--
-- --- Simple fuzzy filter
-- ---@param items string[]
-- ---@param input string
-- ---@return {item:string,score:integer}[]
-- function M.fuzzy_filter(items, input)
--   local results = {}
--   for _, item in ipairs(items) do
--     local s = M.fuzzy_score(item, input)
--     if s then
--       table.insert(results, { item = item, score = s })
--     end
--   end
--   table.sort(results, function(a, b)
--     return a.score > b.score
--   end)
--   return vim.tbl_map(function(item)
--     return item.item
--   end, results)
-- end

return M
