---NOTE: This file assumes `require("vim._extui").enable({})` has been called elsewhere.

local ext = require("vim._extui.shared")
if not ext then
  error(
    "Failed to load vim._extui. Make sure you are running neovim 0.12+ with extui enabled (require'vim._extui'.enable({}))"
  )
end

local uv = vim.uv or vim.loop
local util = require("minibuffer.util")

local M = {}

------------------------------------------------------------
-- Base types
------------------------------------------------------------

---@alias minibuffer.core.SessionType string

---@class minibuffer.core.Session
---@field resumable boolean
---@field closed boolean
---@field type fun(self: minibuffer.core.Session): minibuffer.core.SessionType
---@field overridable fun(self: minibuffer.core.Session): boolean
---@field pre_start fun(self: minibuffer.core.Session)
---@field render fun(self: minibuffer.core.Session)
---@field post_start fun(self: minibuffer.core.Session)
---@field cancel fun(self: minibuffer.core.Session)
---@field close fun(self: minibuffer.core.Session)
local Session = {}
Session.__index = Session

---@class minibuffer.core.HighlightChunk
---@field text string
---@field hl string|nil

---@alias minibuffer.core.HighlightLine minibuffer.core.HighlightChunk[]

---@alias minibuffer.core.ItemCompareFn fun(old:any, new:any): boolean
---@alias minibuffer.core.FormatFn fun(item:any): minibuffer.core.HighlightLine
---@alias minibuffer.core.CancelCallback fun()
---@alias minibuffer.core.CloseCallback fun()
---@alias minibuffer.core.ChangeCallback fun(value:string, item:any)

------------------------------------------------------------
-- Constants & State
------------------------------------------------------------

---@class minibuffer.core.SessionTypes
---@field INPUT '"input"'
---@field SELECT '"select"'
---@field DISPLAY '"display"'
local SESSION_TYPES = {
  INPUT = "input",
  SELECT = "select",
  DISPLAY = "display",
}

---@class minibuffer.core.InternalState
---@field pending_render boolean
---@field active_window integer|nil
---@field session minibuffer.core.Session|nil
---@field prev_session minibuffer.core.Session|nil
---@field win_sizes table<integer, integer>
---@field augroup integer
---@field ns integer
local state = {
  initialized = false,
  pending_render = false,
  active_window = nil,
  session = nil,
  prev_session = nil,
  win_sizes = {},
  augroup = vim.api.nvim_create_augroup("minibuffer", { clear = true }),
  ns = vim.api.nvim_create_namespace("minibuffer"),
}

------------------------------------------------------------
-- Select Session
------------------------------------------------------------

---@alias minibuffer.core.SelectFilterFn fun(items:any[], input:string): any[]
---@alias minibuffer.core.SelectCallback fun(items:any[], idx:integer|integer[])
---@alias minibuffer.core.SelectStartCallback fun(buf: integer, session: minibuffer.core.SelectSession, keyset: minibuffer.util.Keyset)
---@alias minibuffer.core.AsyncSelectFetchFn fun(input:string, cb:fun(items:any[]))

---@class minibuffer.core.SelectSession : minibuffer.core.Session
---@field prompt string
---@field items any[]
---@field format_fn minibuffer.core.FormatFn
---@field filter_fn minibuffer.core.SelectFilterFn
---@field async_fetch minibuffer.core.AsyncSelectFetchFn|nil
---@field on_start minibuffer.core.SelectStartCallback|nil
---@field on_select minibuffer.core.SelectCallback|nil
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil
---@field max_height integer
---@field multi boolean
---@field allow_shrink boolean
---@field display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field input string
---@field filtered_items any[]
---@field current_index integer
---@field selected_indices integer[]
---@field cmd_bufopts table
---@field cmd_winopts table
---@field scroll_offset integer
---@field display_height integer|nil
---@field loading boolean
---@field _req_id integer
local SelectSession = {}
SelectSession.__index = SelectSession
M.SelectSession = SelectSession

---@class minibuffer.core.SelectSessionOpts
---@field resumable boolean|nil
---@field prompt string|nil
---@field items any[]|nil
---@field format_fn minibuffer.core.FormatFn
---@field filter_fn minibuffer.core.SelectFilterFn
---@field async_fetch minibuffer.core.AsyncSelectFetchFn|nil
---@field on_start minibuffer.core.SelectStartCallback|nil
---@field on_select minibuffer.core.SelectCallback
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil
---@field max_height integer|nil
---@field multi boolean|nil
---@field allow_shrink boolean|nil

---@param opts minibuffer.core.SelectSessionOpts|nil
---@return minibuffer.core.SelectSession
function SelectSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    closed = false,
    resumable = opts.resumable == true,
    prompt = (opts.prompt or "Select:") .. " ",
    items = opts.items or {},
    format_fn = opts.format_fn,
    filter_fn = opts.filter_fn,
    async_fetch = opts.async_fetch,
    on_start = opts.on_start,
    on_select = opts.on_select,
    on_cancel = opts.on_cancel,
    on_close = opts.on_close,
    on_change = opts.on_change,
    max_height = opts.max_height or 15,
    multi = opts.multi == true,
    allow_shrink = opts.allow_shrink == true,

    display = { buf = nil, win = nil, ns = nil },
    input = "",
    filtered_items = opts.items or {},
    current_index = 1,
    selected_indices = {},
    cmd_bufopts = {},
    cmd_winopts = {},
    scroll_offset = 0,
    display_height = nil,
    loading = false,
    _req_id = 0,
  }, SelectSession)
  return self
end

---@return minibuffer.core.SessionType
function SelectSession:type()
  return SESSION_TYPES.SELECT
end

---@return boolean
function SelectSession:overridable()
  return false
end

function SelectSession:pre_start()
  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end
  self:update_filter()

  self.closed = false

  self.cmd_bufopts = util.save_cmd_opts("buf", { "buftype", "complete" })
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].complete = ""
  self.cmd_winopts = util.save_cmd_opts("win", { "wrap" })
  vim.wo[win].wrap = false
  state.win_sizes = util.get_window_sizes()

  local display_height = math.max(1, math.min(self.max_height, #self.filtered_items))
  self.display_height = display_height

  util.wipe_cmd_buffer()
  util.enable_cmd_buffer_ts(false)
  util.set_win_height(win, display_height + 1, true)
  vim.wo[win].winhighlight = "Normal:MinibufferPrompt"
  vim.fn.prompt_setprompt(buf, self.prompt)
  vim.fn.prompt_setcallback(buf, function(_)
    self:accept()
  end)

  self.display.buf = vim.api.nvim_create_buf(false, false)
  self.display.win = vim.api.nvim_open_win(self.display.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = display_height,
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = 999,
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
end

function SelectSession:ensure_visible()
  if not self.display_height then
    self.display_height = math.min(self.max_height, #self.filtered_items)
  end
  local height = self.display_height
  local total = #self.filtered_items
  if total <= height then
    self.scroll_offset = 0
    return
  end
  if self.current_index < self.scroll_offset + 1 then
    self.scroll_offset = self.current_index - 1
  elseif self.current_index > self.scroll_offset + height then
    self.scroll_offset = self.current_index - height
  end
  local max_offset = math.max(0, total - height)
  if self.scroll_offset > max_offset then
    self.scroll_offset = max_offset
  end
  if self.scroll_offset < 0 then
    self.scroll_offset = 0
  end
end

function SelectSession:render()
  if not self.display.buf then
    return
  end

  local win = util.get_cmd_win()
  if not win then
    return
  end

  local total = #self.filtered_items
  local extra_loading = self.loading and 1 or 0
  local visible_height = math.min(self.max_height, total + extra_loading)
  if
    not self.allow_shrink
    and self.display.win
    and vim.api.nvim_win_is_valid(self.display.win)
  then
    visible_height =
      math.max(vim.api.nvim_win_get_height(self.display.win), visible_height)
  end
  self.display_height = math.min(self.max_height, total) -- only items affect scrolling
  self:ensure_visible()

  local start_idx = self.scroll_offset + 1
  local end_idx = math.min(total, start_idx + self.display_height - 1)

  local lines_data = {}
  for i = start_idx, end_idx do
    lines_data[#lines_data + 1] = self.format_fn(self.filtered_items[i])
  end
  if self.loading then
    lines_data[#lines_data + 1] =
      { { text = " … loading …", hl = "MinibufferLoading" } }
  end

  util.write_highlighted_lines(self.display.buf, state.ns, lines_data)

  -- Highlight current & multi selections (only if within visible items range)
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
  for _, i in ipairs(self.selected_indices) do
    if i ~= self.current_index and i >= start_idx and i <= end_idx then
      pcall(vim.api.nvim_buf_set_extmark, self.display.buf, state.ns, i - start_idx, 0, {
        line_hl_group = "MinibufferMultiSelected",
      })
    end
  end

  local new_height = math.min(self.max_height, total + extra_loading)
  if not self.allow_shrink then
    new_height = math.max(vim.api.nvim_win_get_height(self.display.win), new_height)
  end
  util.set_win_height(self.display.win, new_height, false)
  util.set_win_height(win, new_height + 1, true)
  util.resize_windows_for_cmdheight(state.win_sizes, new_height - ext.cmdheight)
  if self.on_change then
    pcall(self.on_change, self.input, self.filtered_items[self.current_index])
  end
  vim.cmd.redraw()
end

function SelectSession:post_start()
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end

  local base = { buffer = buf, nowait = true, silent = true, noremap = true }
  local keyset = util.create_condition_keyset(function()
    return state.session == self
  end)

  keyset("i", "<Esc>", function()
    self:cancel()
  end, base)
  keyset("i", "<CR>", function()
    self:accept()
  end, base)
  keyset("i", "<C-y>", function()
    self:accept()
  end, base)
  keyset("i", "<Up>", function()
    self:move(-1)
  end, base)
  keyset("i", "<Down>", function()
    self:move(1)
  end, base)
  keyset("i", "<C-p>", function()
    self:move(-1)
  end, base)
  keyset("i", "<C-n>", function()
    self:move(1)
  end, base)
  keyset("i", "<C-w>", "<C-S-w>", base)

  if self.multi then
    keyset("i", "<C-x>", function()
      self:toggle_selection()
    end, base)
  end

  if self.on_start then
    pcall(self.on_start, buf, self, keyset)
  end
  state.active_window = util.focus_cmd_win()

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, _, _, _, _)
      if self.closed then
        return true
      end
      local input = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if vim.startswith(input, self.prompt) then
        input = input:sub(#self.prompt + 1)
      end
      if input ~= self.input then
        self.input = input
        self:update_filter()
        vim.schedule(function()
          self:render()
        end)
      end
    end,
  })
  vim.cmd("startinsert!")
  pcall(vim.api.nvim_feedkeys, self.input, "t", false)
end

function SelectSession:apply_items(new_items)
  self.items = new_items or {}
  self.filtered_items = self.filter_fn(self.items, self.input) or {}
  if self.multi then
    self.selected_indices = {}
  end
  if #self.filtered_items == 0 then
    self.current_index = 0
    self.scroll_offset = 0
  else
    self.current_index = 1
    self.scroll_offset = 0
  end
  self.loading = false
end

function SelectSession:update_filter()
  if self.async_fetch then
    self.loading = true
    self._req_id = self._req_id + 1
    local req_id = self._req_id
    local ok = pcall(self.async_fetch, self.input, function(result)
      -- discard stale
      if req_id ~= self._req_id then
        return
      end
      self:apply_items(result)
      vim.schedule(function()
        self:render()
      end)
    end)
    if not ok then
      -- fallback: synchronous filter on existing items
      self:apply_items(self.items)
    end
  else
    -- synchronous path
    self.filtered_items = self.filter_fn(self.items, self.input) or {}
    if self.multi then
      self.selected_indices = {}
    end
    if #self.filtered_items == 0 then
      self.current_index = 0
      self.scroll_offset = 0
    else
      self.current_index = 1
      self.scroll_offset = 0
    end
  end
end

function SelectSession:accept()
  if #self.filtered_items == 0 or self.loading then
    return
  end

  local result
  local idx
  if self.multi and #self.selected_indices > 0 then
    result = {}
    for _, i in ipairs(self.selected_indices) do
      if i <= #self.filtered_items then
        result[#result + 1] = self.filtered_items[i]
      end
    end
    idx = self.selected_indices
  else
    if self.current_index > 0 and self.current_index <= #self.filtered_items then
      result = { self.filtered_items[self.current_index] }
      idx = { self.current_index }
    else
      return
    end
  end

  local cb = self.on_select
  self:close()

  if cb then
    vim.schedule(function()
      pcall(cb, result, idx)
    end)
  end
end

---@param delta integer
function SelectSession:move(delta)
  if #self.filtered_items == 0 then
    return
  end
  self.current_index =
    math.max(1, math.min(#self.filtered_items, self.current_index + delta))
  self:render()
end

---@param index integer
---@return boolean
function SelectSession:is_selected(index)
  if not self.multi then
    return false
  end
  for _, sel_idx in ipairs(self.selected_indices) do
    if sel_idx == index then
      return true
    end
  end
  return false
end

function SelectSession:toggle_selection()
  if not self.multi or self.current_index == 0 or #self.filtered_items == 0 then
    return
  end
  local idx = self.current_index
  if self:is_selected(idx) then
    for i, sel_idx in ipairs(self.selected_indices) do
      if sel_idx == idx then
        table.remove(self.selected_indices, i)
        break
      end
    end
  else
    self.selected_indices[#self.selected_indices + 1] = idx
  end
  self:render()
end

function SelectSession:cancel()
  local cb = self.on_cancel
  self:close()

  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
end

function SelectSession:close()
  if self.closed then
    return
  end
  self.closed = true

  vim.cmd("stopinsert")

  if self.display.win and vim.api.nvim_win_is_valid(self.display.win) then
    pcall(vim.api.nvim_win_close, self.display.win, true)
  end
  if self.display.buf and vim.api.nvim_buf_is_valid(self.display.buf) then
    pcall(vim.api.nvim_buf_delete, self.display.buf, { force = true })
  end

  util.restore_cmd_opts("buf", self.cmd_bufopts)
  util.restore_cmd_opts("win", self.cmd_winopts)

  self.display.win = nil
  self.display.buf = nil

  local cb = self.on_close
  M.cleanup()

  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
end

------------------------------------------------------------
-- Input Session
------------------------------------------------------------

---@alias minibuffer.core.InputSubmitCallback fun(input:string)
---@alias minibuffer.core.InputGetSuggestionsFn fun(input:string): any[]
---@alias minibuffer.core.InputAcceptSuggestionFn fun(old_input:string, suggestion:string): string
---@alias minibuffer.core.InputStartCallback fun(buf: integer, session: minibuffer.core.InputSession, keyset: minibuffer.util.Keyset)
---@alias minibuffer.core.AsyncInputSuggestionsFn fun(input:string, cb:fun(suggestions:any[]))

---@class minibuffer.core.InputSession : minibuffer.core.Session
---@field prompt string
---@field input string
---@field format_fn minibuffer.core.FormatFn
---@field get_suggestions minibuffer.core.InputGetSuggestionsFn|nil
---@field async_get_suggestions minibuffer.core.AsyncInputSuggestionsFn|nil
---@field on_start minibuffer.core.InputStartCallback|nil
---@field on_accept_suggestion minibuffer.core.InputAcceptSuggestionFn|nil
---@field on_submit minibuffer.core.InputSubmitCallback|nil
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil
---@field max_height integer
---@field allow_shrink boolean
---@field enable_ts boolean
---@field display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field suggestions any[]
---@field current_index integer
---@field cmd_bufopts table
---@field cmd_winopts table
---@field scroll_offset integer
---@field display_height integer|nil
---@field loading boolean
---@field _req_id integer
local InputSession = {}
InputSession.__index = InputSession
M.InputSession = InputSession

---@class minibuffer.core.InputSessionOpts
---@field resumable boolean|nil
---@field prompt string|nil
---@field initial_text string|nil
---@field format_fn minibuffer.core.FormatFn
---@field get_suggestions minibuffer.core.InputGetSuggestionsFn|nil
---@field async_get_suggestions minibuffer.core.AsyncInputSuggestionsFn|nil
---@field on_start minibuffer.core.InputStartCallback|nil
---@field on_accept_suggestion minibuffer.core.InputAcceptSuggestionFn|nil
---@field on_submit minibuffer.core.InputSubmitCallback
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil
---@field max_height integer|nil
---@field allow_shrink boolean|nil
---@field enable_ts boolean|nil

---@param opts minibuffer.core.InputSessionOpts|nil
---@return minibuffer.core.InputSession
function InputSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    closed = false,
    resumable = opts.resumable == true,
    prompt = opts.prompt or "Enter: ",
    input = opts.initial_text or "",
    format_fn = opts.format_fn,
    get_suggestions = opts.get_suggestions,
    async_get_suggestions = opts.async_get_suggestions,
    on_start = opts.on_start,
    on_accept_suggestion = opts.on_accept_suggestion,
    on_submit = opts.on_submit,
    on_cancel = opts.on_cancel,
    on_close = opts.on_close,
    on_change = opts.on_change,
    max_height = opts.max_height or 15,
    allow_shrink = opts.allow_shrink == true,
    enable_ts = opts.enable_ts == true,

    display = { buf = nil, win = nil, ns = nil },
    suggestions = {},
    current_index = 0,
    cmd_bufopts = {},
    cmd_winopts = {},
    scroll_offset = 0,
    display_height = nil,
    loading = false,
    _req_id = 0,
  }, InputSession)

  self:refresh_suggestions()
  return self
end

---@return minibuffer.core.SessionType
function InputSession:type()
  return SESSION_TYPES.SELECT
end

---@return boolean
function InputSession:overridable()
  return false
end

function InputSession:pre_start()
  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  self.closed = false

  self.cmd_bufopts = util.save_cmd_opts("buf", { "buftype", "complete" })
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].complete = ""
  self.cmd_winopts = util.save_cmd_opts("win", { "wrap" })
  vim.wo[win].wrap = false
  state.win_sizes = util.get_window_sizes()

  local display_height = math.min(self.max_height, #self.suggestions)
  self.display_height = display_height

  util.wipe_cmd_buffer()
  util.enable_cmd_buffer_ts(self.enable_ts)
  if not self.enable_ts then
    vim.wo[win].winhighlight = "Normal:MinibufferPrompt"
  end
  util.set_win_height(win, display_height + 1, true)
  vim.fn.prompt_setprompt(buf, self.prompt)
  vim.fn.prompt_setcallback(buf, function(_)
    self:submit()
  end)

  self.display.buf = vim.api.nvim_create_buf(false, true)
  self.display.win = vim.api.nvim_open_win(self.display.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    hide = true,
    height = math.max(1, display_height),
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = 999,
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
end

function InputSession:ensure_visible()
  if not self.display_height then
    self.display_height = math.min(self.max_height, #self.suggestions)
  end
  local height = self.display_height
  local total = #self.suggestions
  if total <= height then
    self.scroll_offset = 0
    return
  end
  if self.current_index < self.scroll_offset + 1 then
    self.scroll_offset = self.current_index - 1
  elseif self.current_index > self.scroll_offset + height then
    self.scroll_offset = self.current_index - height
  end
  local max_offset = math.max(0, total - height)
  if self.scroll_offset > max_offset then
    self.scroll_offset = max_offset
  end
  if self.scroll_offset < 0 then
    self.scroll_offset = 0
  end
end

function InputSession:render()
  if not self.display.buf then
    return
  end
  local win = util.get_cmd_win()
  if not win then
    return
  end

  local total = #self.suggestions
  local extra_loading = self.loading and 1 or 0
  local visible_height = math.min(self.max_height, total + extra_loading)
  if not self.allow_shrink then
    visible_height = math.max(vim.api.nvim_win_get_height(win) - 1, visible_height)
  end
  self.display_height = math.min(self.max_height, total)
  self:ensure_visible()

  local start_idx = self.scroll_offset + 1
  local end_idx = math.min(total, start_idx + self.display_height - 1)

  local lines_data = {}
  for i = start_idx, end_idx do
    lines_data[#lines_data + 1] = self.format_fn(self.suggestions[i])
  end
  if self.loading then
    lines_data[#lines_data + 1] =
      { { text = " … loading …", hl = "MinibufferLoading" } }
  end

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

  local new_height = math.min(self.max_height, total + extra_loading)
  if not self.allow_shrink then
    new_height = math.max(vim.api.nvim_win_get_height(win) - 1, new_height)
  end
  util.set_win_height(self.display.win, new_height, false)
  util.set_win_height(win, new_height + 1, true)
  util.resize_windows_for_cmdheight(state.win_sizes, new_height - ext.cmdheight)
  if self.on_change then
    pcall(self.on_change, self.input, self.suggestions[self.current_index])
  end
  vim.cmd.redraw()
end

function InputSession:post_start()
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end

  local base = { buffer = buf, nowait = true, silent = true, noremap = true }
  local keyset = util.create_condition_keyset(function()
    return state.session == self
  end)

  keyset("i", "<Esc>", function()
    self:cancel()
  end, base)
  keyset("i", "<CR>", function()
    self:submit()
  end, base)
  keyset("i", "<Up>", function()
    self:move(-1)
  end, base)
  keyset("i", "<Down>", function()
    self:move(1)
  end, base)
  keyset("i", "<C-p>", function()
    self:move(-1)
  end, base)
  keyset("i", "<C-n>", function()
    self:move(1)
  end, base)
  keyset("i", "<C-y>", function()
    self:accept_suggestion()
  end, base)
  keyset("i", "<C-w>", "<C-S-w>", base)

  if self.on_start then
    pcall(self.on_start, buf, self, keyset)
  end
  state.active_window = util.focus_cmd_win()

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, _, _, _, _)
      if self.closed then
        return true
      end
      local input = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if vim.startswith(input, self.prompt) then
        input = input:sub(#self.prompt + 1)
      end
      if input ~= self.input then
        self.input = input
        self:refresh_suggestions()
        vim.schedule(function()
          self:render()
        end)
      end
    end,
  })
  vim.cmd("startinsert!")
  pcall(vim.api.nvim_feedkeys, self.input, "t", false)
end

function InputSession:refresh_suggestions()
  local function apply(list)
    list = list or {}
    self.suggestions = list
    if #list == 0 then
      self.current_index = 0
      self.scroll_offset = 0
    else
      self.current_index = 1
      self.scroll_offset = 0
    end
    self.loading = false
  end

  if self.async_get_suggestions then
    self.loading = true
    self._req_id = self._req_id + 1
    local rid = self._req_id
    local ok = pcall(self.async_get_suggestions, self.input, function(result)
      if rid ~= self._req_id then
        return
      end
      apply(result)
      vim.schedule(function()
        self:render()
      end)
    end)
    if not ok then
      apply({})
    end
  else
    local fn_get = self.get_suggestions
    local list = {}
    if fn_get then
      local ok, res = pcall(fn_get, self.input)
      if ok and type(res) == "table" then
        list = res
      end
    end
    self.suggestions = list
    if #list == 0 then
      self.current_index = 0
      self.scroll_offset = 0
    else
      self.current_index = 1
      self.scroll_offset = 0
    end
  end
end

function InputSession:accept_suggestion()
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  if self.current_index == 0 or #self.suggestions == 0 or self.loading then
    return
  end

  local text = self.suggestions[self.current_index]
  local cb = self.on_accept_suggestion
  local newi
  if cb then
    local ok, res = pcall(cb, self.input, text)
    if ok and type(res) == "string" then
      newi = res
    else
      newi = self.input .. text
    end
  else
    newi = self.input + text
  end

  if type(newi) ~= "string" then
    newi = self.input .. text
  end

  local backspaces = string.rep(
    vim.api.nvim_replace_termcodes("<BS>", true, false, true),
    self.input:len() + 1
  )
  self.input = newi
  vim.api.nvim_feedkeys(backspaces, "i", true)
  vim.api.nvim_feedkeys(self.input, "n", true)
  self:refresh_suggestions()
  self:render()
end

---@param delta integer
function InputSession:move(delta)
  if #self.suggestions == 0 then
    return
  end
  self.current_index =
    math.max(1, math.min(#self.suggestions, self.current_index + delta))
  self:render()
end

function InputSession:submit()
  local final = self.input
  local cb = self.on_submit
  self:close()

  if cb then
    vim.schedule(function()
      pcall(cb, final)
    end)
  end
end

function InputSession:cancel()
  local cb = self.on_cancel
  self:close()

  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
end

function InputSession:close()
  if self.closed then
    return
  end
  self.closed = true

  vim.cmd("stopinsert")

  if self.display.win and vim.api.nvim_win_is_valid(self.display.win) then
    pcall(vim.api.nvim_win_close, self.display.win, true)
  end
  if self.display.buf and vim.api.nvim_buf_is_valid(self.display.buf) then
    pcall(vim.api.nvim_buf_delete, self.display.buf, { force = true })
  end

  util.restore_cmd_opts("buf", self.cmd_bufopts)
  util.restore_cmd_opts("win", self.cmd_winopts)

  self.display.win = nil
  self.display.buf = nil

  local cb = self.on_close
  M.cleanup()

  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
end

------------------------------------------------------------
-- Display Session (unchanged except for highlight additions)
------------------------------------------------------------

---@class minibuffer.core.DisplaySession : minibuffer.core.Session
---@field lines minibuffer.core.HighlightLine[]
---@field timeout integer|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field close_keys string[]
---@field allow_shrink boolean
---@field timer uv.uv_timer_t|nil
local DisplaySession = {}
DisplaySession.__index = DisplaySession
M.DisplaySession = DisplaySession

---@class minibuffer.core.DisplaySessionOpts
---@field lines minibuffer.core.HighlightLine[]
---@field timeout integer|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field close_keys string[]|nil
---@field allow_shrink boolean|nil

---@param opts minibuffer.core.DisplaySessionOpts|nil
---@return minibuffer.core.DisplaySession
function DisplaySession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    closed = false,
    resumable = false,
    lines = opts.lines or {},
    timeout = opts.timeout,
    on_close = opts.on_close,
    close_keys = opts.close_keys or { "<F5>" },
    allow_shrink = opts.allow_shrink == true,

    timer = nil,
  }, DisplaySession)
  return self
end

---@return minibuffer.core.SessionType
function DisplaySession:type()
  return SESSION_TYPES.SELECT
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
  state.win_sizes = util.get_window_sizes()

  self.closed = false

  if self.timeout and self.timeout > 0 then
    local timer = uv.new_timer()
    self.timer = timer
    self.timer:start(self.timeout, 0, function()
      vim.schedule(function()
        if state.session == self then
          self:close()
        else
          if timer then
            pcall(timer.stop, timer)
            pcall(timer.close, timer)
          end
        end
      end)
    end)
  end

  util.wipe_cmd_buffer()
  util.enable_cmd_buffer_ts(false)
end

function DisplaySession:render()
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
  if not self.allow_shrink then
    new_height = math.max(vim.api.nvim_win_get_height(win), new_height)
  end
  util.set_win_height(win, new_height, false)
  util.set_win_height(win, new_height + 1, true)
  util.resize_windows_for_cmdheight(state.win_sizes, new_height - ext.cmdheight)
  vim.cmd.redraw()
end

function DisplaySession:post_start()
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  local base = { buffer = buf, nowait = true, silent = true, noremap = true }
  for _, k in ipairs(self.close_keys) do
    vim.keymap.set({ "n" }, k, function()
      if state.session == self then
        self:close()
      end
    end, base)
  end
end

function DisplaySession:cancel()
  self:close()
end

function DisplaySession:close()
  if self.closed then
    return
  end
  self.closed = true

  if self.timer then
    pcall(self.timer.stop, self.timer)
    pcall(self.timer.close, self.timer)
    self.timer = nil
  end

  local cb = self.on_close
  M.cleanup()

  if cb then
    vim.schedule(function()
      pcall(cb)
    end)
  end
end

---@param lines minibuffer.core.HighlightLine[]
---@return boolean
function DisplaySession:update_lines(lines)
  if self.closed then
    return false
  end
  self.lines = lines
  self:render()
  return true
end

------------------------------------------------------------
-- Module
------------------------------------------------------------

function M.initialize()
  if not state.initialized then
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
  state.initialized = true
end

---@param session minibuffer.core.Session
---@param force boolean|nil
---@return boolean started
function M.start_session(session, force)
  if force == nil then
    force = false
  end
  if not util.ready() then
    vim.schedule(function()
      vim.notify("[mb] ext cmd buffer not ready yet.", vim.log.levels.WARN)
    end)
    return false
  end
  if not force and state.session and not state.session:overridable() then
    vim.notify("[mb] Session active (use force=true).", vim.log.levels.INFO)
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

  vim.api.nvim_create_autocmd("VimResized", {
    group = state.augroup,
    callback = function()
      session:render()
    end,
  })

  return true
end

function M.cleanup()
  if not state.session then
    return
  end
  local win = util.get_cmd_win()
  if not win then
    return
  end

  vim.api.nvim_clear_autocmds({ group = state.augroup })
  util.wipe_cmd_buffer()
  util.set_win_height(win, ext.cmdheight, true)
  util.restore_window_sizes(state.win_sizes)
  if state.active_window and vim.api.nvim_win_is_valid(state.active_window) then
    pcall(vim.api.nvim_set_current_win, state.active_window)
  end
  state.active_window = nil

  if state.session.resumable then
    state.prev_session = state.session
  end
  state.session = nil
  state.pending_render = false
  state.active_window = nil
end

function M.resume(force)
  if not state.prev_session then
    return false
  end
  return M.start_session(state.prev_session, force)
end

---@return boolean
function M.is_active()
  return state.session ~= nil
end

---@return minibuffer.core.Session|nil
function M.get_active_session()
  return state.session
end

---@return integer|nil
function M.get_active_window()
  return state.active_window
end

return M
