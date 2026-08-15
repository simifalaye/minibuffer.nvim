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

  local is_lua = vim.startswith(text, "lua ") or vim.startswith(text, "luado ")

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
  local parts = vim.split(cmp_input, "|")
  local last_cmd = parts[#parts]

  if not last_cmd:match("^%S+ ") then
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
    if item.lower:sub(1, #query) == query then
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

local function on_accept_suggestion(firstc, suggestion)
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
---@field input string
---@field cursor_pos integer
---@field max_height integer
---@field allow_shrink boolean
---@field win_sizes table<integer, integer>
---@field display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field suggestions any[]
---@field current_index integer
---@field global_opts table
---@field scroll_offset integer
---@field display_height integer
---@field display_height_prev integer
---@field loading boolean
---@field _save_win_views table<integer, { buf: integer, view: vim.fn.winsaveview.ret }>
local CmdSession = {}
CmdSession.__index = CmdSession

---@class minibuffer.core.CmdSessionOpts
---@field firstc string
---@field initial_input string?
---@field initial_cursor_pos integer?
---@field max_height integer|nil
---@field allow_shrink boolean|nil
---@field win_sizes table<integer, integer>

---@param opts minibuffer.core.CmdSessionOpts|nil
---@return minibuffer.core.CmdSession
function CmdSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    resumable = false,
    closed = false,
    firstc = opts.firstc,
    input = opts.initial_input or "",
    cursor_pos = opts.initial_cursor_pos or 1,
    max_height = opts.max_height or 15,
    allow_shrink = opts.allow_shrink == true,
    win_sizes = opts.win_sizes,
    display = { buf = nil, win = nil, ns = nil },
    suggestions = {},
    current_index = 0,
    global_opts = {},
    scroll_offset = 0,
    display_height = 0,
    display_height_prev = 0,
    loading = false,
  }, CmdSession)
  assert(opts.firstc ~= nil, "Must provide firstc")
  assert(opts.win_sizes ~= nil, "Must provide win_sizes")

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

  self.closed = false

  local display_height = math.min(self.max_height, #self.suggestions)
  display_height = math.max(display_height, 1)
  self.display_height = display_height

  self.display.buf = vim.api.nvim_create_buf(false, true)
  self.display.win = vim.api.nvim_open_win(self.display.buf, false, {
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
  vim.api.nvim_win_call(self.display.win, function()
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
  self.global_opts = util.save_cmd_opts("global", {
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

  self:refresh_suggestions()
end

function CmdSession:render()
  if not self.display.buf then
    return
  end
  local win = util.get_cmd_win()
  if not win then
    return
  end

  -- Calculate height based on the suggestions, loading state and max height
  local total = #self.suggestions
  local extra_loading = self.loading and 1 or 0
  local visible_height = math.min(self.max_height, total + extra_loading)
  if not self.allow_shrink then
    visible_height = math.max(self.display_height_prev, visible_height)
  end
  self.display_height = math.min(self.max_height, visible_height)

  -- Correct for scroll position
  if total <= self.display_height then
    self.scroll_offset = 0
  else
    if self.current_index < self.scroll_offset + 1 then
      self.scroll_offset = self.current_index - 1
    elseif self.current_index > self.scroll_offset + self.display_height then
      self.scroll_offset = self.current_index - self.display_height
    end
    local max_offset = math.max(0, total - self.display_height)
    if self.scroll_offset > max_offset then
      self.scroll_offset = max_offset
    end
    if self.scroll_offset < 0 then
      self.scroll_offset = 0
    end
  end

  -- Set heights
  util.set_win_height(self.display.win, self.display_height, false)
  util.set_win_height(win, self.display_height + 1, true)
  util.resize_windows_for_cmdheight(self.win_sizes, self.display_height - ext.cmdheight)
  self.display_height_prev = self.display_height

  -- Build display output
  local start_idx = self.scroll_offset + 1
  local end_idx = math.min(total, start_idx + self.display_height - 1)
  local lines_data = {}
  for i = start_idx, end_idx do
    lines_data[#lines_data + 1] = format_fn(self.suggestions[i])
  end
  if self.loading then
    lines_data[#lines_data + 1] =
      { { text = " … loading …", hl = "MinibufferLoading" } }
  end

  -- Write lines and highlights
  util.write_highlighted_lines(self.display.buf, state.ns, lines_data)
  if self.current_index >= start_idx and self.current_index <= end_idx then
    pcall(
      vim.api.nvim_buf_set_extmark,
      self.display.buf,
      state.ns,
      self.current_index - start_idx,
      0,
      { line_hl_group = "MinibufferSelection" }
    )
  end

  -- Force redraw
  vim.cmd.redraw()
end

function CmdSession:post_start()
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
      saved_input = self.input
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
      return self.input
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
    if self.input:len() == 0 or current_history_item == self.input then
      self:set_input(prev_cmd())
    else
      current_history_item = nil
      self:move(-1)
    end
  end
  local function move_next()
    if self.input:len() == 0 or current_history_item == self.input then
      self:set_input(next_cmd())
    else
      current_history_item = nil
      self:move(1)
    end
  end

  -- Override wild keymaps
  local base = { nowait = true, silent = true, noremap = true }
  vim.keymap.set("c", "<C-n>", function()
    move_next()
  end)
  vim.keymap.set("c", "<Up>", function()
    move_prev()
  end, base)
  vim.keymap.set("c", "<Down>", function()
    move_next()
  end, base)
  vim.keymap.set("c", "<C-p>", function()
    move_prev()
  end, base)
  vim.keymap.set("c", "<C-n>", function()
    move_next()
  end, base)
  vim.keymap.set("c", "<S-Tab>", function()
    move_prev()
  end, base)
  vim.keymap.set("c", "<Tab>", function()
    move_next()
  end, base)
  vim.keymap.set("c", "<C-y>", function()
    self:accept_suggestion()
  end, base)
end

function CmdSession:cancel()
  self:close()
end

function CmdSession:close()
  if self.closed then
    return
  end
  self.closed = true

  if self.display.win and vim.api.nvim_win_is_valid(self.display.win) then
    pcall(vim.api.nvim_win_close, self.display.win, true)
  end
  if self.display.buf and vim.api.nvim_buf_is_valid(self.display.buf) then
    pcall(vim.api.nvim_buf_delete, self.display.buf, { force = true })
  end

  util.restore_cmd_opts("global", self.global_opts)

  self.display.win = nil
  self.display.buf = nil

  if get_cmd_type(self.firstc) == "search" then
    schedule_reset_search_state()
  else
    reset_command_state()
  end

  state.cleanup()
end

function CmdSession:set_input(text)
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end

  self.input = text
  if get_cmd_type(self.firstc) == "search" then
    vim.api.nvim_feedkeys(vim.keycode("<C-e><C-u>") .. text, "n", false)
  else
    vim.api.nvim_feedkeys(vim.keycode("<C-u>") .. text, "n", false)
  end

  self:refresh_suggestions()
end

function CmdSession:refresh_suggestions()
  local fn

  if get_cmd_type(self.firstc) == "search" then
    fn = get_search_suggestions
  else
    fn = get_command_suggestions
  end
  local suggestions = fn(self.input, self.cursor_pos)
  -- failed to query suggestions so preserve previous
  if suggestions == nil then
    return
  end
  self.suggestions = suggestions
  if #self.suggestions == 0 then
    self.current_index = 0
    self.scroll_offset = 0
  else
    self.current_index = 1
    self.scroll_offset = 0
  end
end

function CmdSession:accept_suggestion()
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  if self.current_index == 0 or #self.suggestions == 0 or self.loading then
    return
  end

  local text = self.suggestions[self.current_index]
  local newi = on_accept_suggestion(self.firstc, text)
  self:set_input(newi)
  self.suggestions = {}
  self:render()
end

---@param delta integer
function CmdSession:move(delta)
  local count = #self.suggestions
  if count == 0 then
    return
  end

  self.current_index = ((self.current_index - 1 + delta) % count) + 1
  self:render()
end

function CmdSession:submit()
  self:close()
end

return CmdSession
