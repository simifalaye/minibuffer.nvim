---@class minibuffer.builtin.cmdline.CompletionContext
---@field start integer
---@field finish integer
---@field query string
---@field prefix string
---@field is_lua boolean

---@class minibuffer.builtin.cmdline.Suggestion
---@field value string
---@field description string?

local state = require("minibuffer.state")
local util = require("minibuffer.util")
local ext = util.get_ext()

local completion_state = {
  command = {
    ctx = {
      start = -1,
      finish = -1,
      prefix = "",
      query = "",
      is_lua = false,
    },
    cache = nil,
  },

  search = {
    buffer = nil,
    changedtick = nil,
    suggestions = {},
    cleanup_timer = nil,
  },
}

local function reset_command_state()
  completion_state.command.ctx = {
    start = -1,
    finish = -1,
    prefix = "",
    query = "",
    is_lua = false,
  }
  completion_state.command.cache = nil
end

local function reset_search_state()
  completion_state.search.buffer = nil
  completion_state.search.changedtick = nil
  completion_state.search.suggestions = {}
end

local function schedule_reset_search_state()
  local search = completion_state.search

  if search.cleanup_timer then
    search.cleanup_timer:stop()
    search.cleanup_timer:close()
  end

  search.cleanup_timer = vim.uv.new_timer()
  if not search.cleanup_timer then
    return
  end

  search.cleanup_timer:start(30000, 0, function()
    vim.schedule(function()
      reset_search_state()
      if search.cleanup_timer then
        search.cleanup_timer:close()
        search.cleanup_timer = nil
      end
    end)
  end)
end

--
-- Command completion
--

local function build_command_ctx(text, pos)
  local reset = {
    [" "] = true,
    ["("] = true,
    [")"] = true,
    ["{"] = true,
    ["}"] = true,
    ["["] = true,
    ["]"] = true,
    [","] = true,
    [";"] = true,
    ["|"] = true,
    ["`"] = true,
    ["="] = true,
    ["!"] = true,
  }

  -- `:=` followed by non-whitespace is a lua command, see `:h :=`
  local lua_prefixes = { "lua ", "luado", "=%s*%S" }
  local is_lua = vim.iter(lua_prefixes):any(function(prefix)
    return string.match(text, "^" .. prefix) ~= nil
  end)

  if is_lua then
    reset["."] = true
    reset[":"] = true
  end

  local function escaped(p)
    local count = 0
    p = p - 1
    while p > 0 and text:sub(p, p) == "\\" do
      count = count + 1
      p = p - 1
    end
    return count % 2 == 1
  end

  local start = 1
  local finish = #text
  local token_start = 1
  local quote

  for i = 1, #text + 1 do
    local ch = text:sub(i, i)
    if quote then
      if ch == quote and not escaped(i) then
        quote = nil
      end
    elseif i > #text or reset[ch] then
      local token_end = i - 1
      if pos >= token_start and pos <= token_end then
        start = token_start
        finish = token_end
        break
      elseif pos > token_end then
        start = i + 1
        finish = i + 1
      end
      token_start = i + 1
    end
  end

  completion_state.command.ctx = {
    start = start,
    finish = finish,
    query = text:sub(start, finish),
    prefix = text:sub(1, start - 1),
    is_lua = is_lua,
  }
end

local function get_command_suggestions(input, cursor_pos)
  if input == "" then
    return {}
  end

  local cmd = completion_state.command
  if not cmd.cache then
    cmd.cache = vim.api.nvim_get_commands({})
  end

  local text = input:sub(1, cursor_pos)

  build_command_ctx(text, cursor_pos)

  local cmp_input = cmd.ctx.prefix .. cmd.ctx.query

  local function make(value)
    local info = cmd.cache[value]
    return {
      value = value,
      description = info and info.definition or "",
    }
  end

  local suggestions = {}

  if not cmp_input:match("^%S+ ") then
    local ok, items = pcall(vim.fn.getcompletion, cmp_input, "command")
    if ok then
      for _, item in ipairs(items) do
        suggestions[#suggestions + 1] = make(item)
      end
    else
      suggestions = nil
    end
  end

  if not suggestions or #suggestions == 0 then
    local ok, items = pcall(vim.fn.getcompletion, cmp_input, "cmdline")
    if ok then
      suggestions = {}
      for _, item in ipairs(items) do
        suggestions[#suggestions + 1] = make(item)
      end
    else
      suggestions = nil
    end
  end

  return suggestions
end

--
-- Search completion
--

local function build_search_index()
  local words = {}
  local seen = {}

  local function add(word)
    local lower = word:lower()
    if lower ~= "" and not seen[lower] then
      seen[lower] = true
      words[#words + 1] = {
        lower = lower,
        value = word,
      }
    end
  end

  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    -- Only collect word-like search candidates.
    -- Punctuation deliberately becomes a boundary.
    for word in line:gmatch("[%a%d_]+") do
      add(word)
    end
  end

  return words
end

local function get_search_index()
  local search = completion_state.search
  local buf = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(buf)

  if search.buffer ~= buf or search.changedtick ~= tick then
    search.buffer = buf
    search.changedtick = tick
    search.suggestions = build_search_index()
  end

  return search.suggestions
end

local function get_search_suggestions(input)
  if input == "" then
    return {}
  end

  -- Only complete the current search token.
  local query = input:match("([%a%d_]+)$")
  if not query then
    return {}
  end

  query = query:lower()

  local results = {}
  for _, item in ipairs(get_search_index()) do
    if item.lower ~= query and item.lower:sub(1, #query) == query then
      results[#results + 1] = {
        value = input:sub(1, #input - #query) .. item.value,
      }
      if #results >= 20 then
        break
      end
    end
  end

  return results
end

--
-- Shared helpers
--

local function get_cmd_type(firstc)
  return (firstc == "/" or firstc == "?") and "search" or "cmd"
end

local function on_accept(firstc, suggestion)
  if get_cmd_type(firstc) == "search" then
    return suggestion.value
  end

  return completion_state.command.ctx.prefix .. suggestion.value
end

local function format_fn(item)
  local fmt = {
    { text = " " .. item.value, hl = "String" },
  }
  if item.description and item.description ~= "" then
    table.insert(fmt, { text = " - " .. item.description, hl = "Comment" })
  end
  return fmt
end

--
-- CmdSession
--

---@class minibuffer.core.CmdSession : minibuffer.core.Session
---@field firstc string
---@field max_height integer
---@field dynamic_height boolean
---@field win_sizes table<integer, integer>
---@field _input string
---@field _cursor_pos integer
---@field _display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field _suggestions any[]
---@field _current_index integer 1-based; 0 means no selection
---@field _scroll_offset integer
---@field _global_opts table
local CmdSession = {}
CmdSession.__index = CmdSession

---@class minibuffer.core.CmdSessionOpts
---@field firstc string
---@field initial_input string?
---@field initial_cursor_pos integer?
---@field max_height integer|nil
---@field dynamic_height boolean|nil
---@field win_sizes table<integer, integer>

---@param opts minibuffer.core.CmdSessionOpts|nil
---@return minibuffer.core.CmdSession
function CmdSession.new(opts)
  opts = opts or {}
  local input = opts.initial_input or ""
  local self = setmetatable({
    resumable = false,
    firstc = opts.firstc,
    max_height = opts.max_height or 15,
    dynamic_height = opts.dynamic_height == true,
    win_sizes = opts.win_sizes,

    _closed = false,
    _input = input,
    _cursor_pos = opts.initial_cursor_pos or #input,
    _display = { buf = nil, win = nil, ns = nil },
    _suggestions = {},
    _current_index = 0,
    _scroll_offset = 0,
    _global_opts = {},
  }, CmdSession)
  assert(self.firstc ~= nil, "Must provide firstc")
  assert(self.win_sizes ~= nil, "Must provide win_sizes")

  return self
end

---@return minibuffer.core.SessionType
function CmdSession:type()
  return "cmd"
end

---@return boolean
function CmdSession:overridable()
  return false
end

function CmdSession:pre_start()
  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  self._closed = false

  local display_height = math.max(1, math.min(self.max_height, #self._suggestions))
  self._display.buf = vim.api.nvim_create_buf(false, true)
  self._display.win = vim.api.nvim_open_win(self._display.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    hide = true,
    height = math.max(1, display_height),
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = vim.api.nvim_win_get_config(win).zindex + 1,
    border = "none",
  })
  vim.api.nvim_win_call(self._display.win, function()
    vim.api.nvim_set_option_value("filetype", "", { scope = "local" })
    vim.api.nvim_set_option_value("eventignorewin", "all", { scope = "local" })
    vim.api.nvim_set_option_value("wrap", false, { scope = "local" })
    vim.api.nvim_set_option_value("linebreak", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "hide", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value("winhighlight", "Normal:Normal", { scope = "local" })
  end)

  -- Force wildmenu options to disable pum
  self._global_opts = util.save_cmd_opts("global", {
    "wildmenu",
    "wildmode",
    "wildoptions",
    "wildchar",
  })
  vim.opt.wildmenu = false
  vim.opt.wildmode = ""
  vim.opt.wildchar = 0
  vim.opt.wildoptions = vim.tbl_filter(function(opt)
    return opt ~= "pum"
    ---@diagnostic disable-next-line: undefined-field
  end, vim.opt.wildoptions:get())
end

function CmdSession:render()
  if self._closed then
    return
  end

  if not self._display.buf then
    return
  end
  local win = util.get_cmd_win()
  if not win then
    return
  end

  -- Calculate height based on the suggestions, loading state and max height
  local prev_display_height = vim.api.nvim_win_get_height(self._display.win)
  local total = #self._suggestions
  local desired_height = math.max(1, math.min(self.max_height, total))
  local display_height = desired_height
  if not self.dynamic_height then
    display_height = math.max(prev_display_height, desired_height)
    display_height = math.min(display_height, self.max_height)
  end

  -- Correct for scroll position
  if total <= display_height then
    self._scroll_offset = 0
  else
    if self._current_index < self._scroll_offset + 1 then
      self._scroll_offset = self._current_index - 1
    elseif self._current_index > self._scroll_offset + display_height then
      self._scroll_offset = self._current_index - display_height
    end
    local max_offset = math.max(0, total - display_height)
    if self._scroll_offset > max_offset then
      self._scroll_offset = max_offset
    end
    if self._scroll_offset < 0 then
      self._scroll_offset = 0
    end
  end

  -- Set heights
  util.set_win_height(self._display.win, display_height, false)
  util.set_win_height(win, display_height + 1, true)
  util.resize_windows_for_cmdheight(self.win_sizes, display_height - ext.cmdheight)

  -- Build display output
  local start_idx = self._scroll_offset + 1
  local end_idx = math.min(total, start_idx + display_height - 1)
  local lines_data = {}
  for i = start_idx, end_idx do
    lines_data[#lines_data + 1] = format_fn(self._suggestions[i])
  end

  -- Write lines and highlights
  util.write_highlighted_lines(self._display.buf, state.ns, lines_data)
  if self._current_index >= start_idx and self._current_index <= end_idx then
    pcall(
      vim.api.nvim_buf_set_extmark,
      self._display.buf,
      state.ns,
      self._current_index - start_idx,
      0,
      { line_hl_group = "MinibufferSelection" }
    )
  end

  -- Force redraw
  vim.cmd.redraw()
end

function CmdSession:post_start()
  if self._closed then
    return
  end

  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  local history_type = get_cmd_type(self.firstc)
  local hist_idx = vim.fn.histnr(history_type) + 1
  local saved_input = nil
  local current_history_item = nil

  local function prev_cmd()
    -- First time entering history: save the current input.
    if saved_input == nil then
      saved_input = self._input
      hist_idx = vim.fn.histnr(history_type) + 1
    end

    if hist_idx > 1 then
      hist_idx = hist_idx - 1
    end

    current_history_item = vim.fn.histget(history_type, hist_idx)

    return current_history_item
  end

  local function next_cmd()
    if saved_input == nil then
      return self._input
    end

    local newest = vim.fn.histnr(history_type)

    if hist_idx < newest then
      hist_idx = hist_idx + 1
      current_history_item = vim.fn.histget(history_type, hist_idx)
      return current_history_item
    end

    -- We've moved past the newest history entry back to the
    -- user's original input.
    local i = saved_input
    saved_input = nil
    current_history_item = nil
    hist_idx = newest + 1

    return i
  end

  -- Smart select:
  -- * When there is no cmdline input, move through history
  -- * While the history item hasn't been modified by the user, continue moving through history
  -- * Else select suggestions
  local function move_prev()
    if self._input:len() == 0 or current_history_item == self._input then
      self:replace_input(prev_cmd())
    else
      current_history_item = nil
      self:move(-1)
    end
  end
  local function move_next()
    if self._input:len() == 0 or current_history_item == self._input then
      self:replace_input(next_cmd())
    else
      current_history_item = nil
      self:move(1)
    end
  end

  local keyset = util.create_condition_keyset(function()
    return state.session == self
  end, { nowait = true, silent = true, noremap = true })

  -- Override wild keymaps
  keyset("c", "<Up>", function()
    move_prev()
  end)
  keyset("c", "<Down>", function()
    move_next()
  end)
  keyset("c", "<C-p>", function()
    move_prev()
  end)
  keyset("c", "<C-n>", function()
    move_next()
  end)
  keyset("c", "<S-Tab>", function()
    move_prev()
  end)
  keyset("c", "<Tab>", function()
    move_next()
  end)
  keyset("c", "<C-y>", function()
    self:accept()
  end)

  self:refresh_suggestions()
end

function CmdSession:cancel()
  if self._closed then
    return
  end

  self:close()
end

function CmdSession:close(done)
  if self._closed then
    return
  end
  self._closed = true

  if self._display.win and vim.api.nvim_win_is_valid(self._display.win) then
    pcall(vim.api.nvim_win_close, self._display.win, true)
  end
  if self._display.buf and vim.api.nvim_buf_is_valid(self._display.buf) then
    pcall(vim.api.nvim_buf_delete, self._display.buf, { force = true })
  end

  util.restore_cmd_opts("global", self._global_opts)

  self._display.win = nil
  self._display.buf = nil

  if get_cmd_type(self.firstc) == "search" then
    schedule_reset_search_state()
  else
    reset_command_state()
  end

  --Remove keymaps
  vim.keymap.del("c", "<Up>")
  vim.keymap.del("c", "<Down>")
  vim.keymap.del("c", "<C-p>")
  vim.keymap.del("c", "<C-n>")
  vim.keymap.del("c", "<S-Tab>")
  vim.keymap.del("c", "<Tab>")
  vim.keymap.del("c", "<C-y>")

  state.cleanup()

  if done then
    vim.schedule(function()
      done()
    end)
  end
end

function CmdSession:set_input(input, cursor_pos)
  if self._closed then
    return
  end
  self._input = input
  self._cursor_pos = cursor_pos
  self:refresh_suggestions()
end

function CmdSession:replace_input(text)
  if self._closed then
    return
  end

  self._input = text
  self._cursor_pos = #text
  -- No need to refresh suggestions here or render since inputting into the cmdline should
  -- trigger cmdline_show which will then call `set_input` and `render`
  if get_cmd_type(self.firstc) == "search" then
    vim.api.nvim_feedkeys(vim.keycode("<C-e><C-u>") .. text, "n", false)
  else
    vim.api.nvim_feedkeys(vim.keycode("<C-u>") .. text, "n", false)
  end
end

function CmdSession:refresh_suggestions()
  if self._closed then
    return
  end

  local fn
  if get_cmd_type(self.firstc) == "search" then
    fn = get_search_suggestions
  else
    fn = get_command_suggestions
  end
  local suggestions = fn(self._input, self._cursor_pos)
  -- failed to query suggestions so preserve previous
  if suggestions == nil then
    return
  end
  self._suggestions = suggestions
  if #self._suggestions == 0 then
    self._current_index = 0
    self._scroll_offset = 0
  else
    self._current_index = 1
    self._scroll_offset = 0
  end

  self:render()
end

function CmdSession:accept()
  if self._closed then
    return
  end

  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  if self._current_index == 0 or #self._suggestions == 0 then
    return
  end

  local text = self._suggestions[self._current_index]
  local newi = on_accept(self.firstc, text)
  self:replace_input(newi)
end

---@param delta integer
function CmdSession:move(delta)
  if self._closed then
    return
  end

  local count = #self._suggestions
  if count == 0 then
    return
  end

  self._current_index = ((self._current_index - 1 + delta) % count) + 1
  self:render()
end

return CmdSession
