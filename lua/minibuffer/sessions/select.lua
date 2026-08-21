local state = require("minibuffer.state")
local util = require("minibuffer.util")

---@param conf { buf:integer|nil, win:integer|nil }
local function win_state_is_valid(conf)
  return conf.buf
    and vim.api.nvim_buf_is_valid(conf.buf)
    and conf.win
    and vim.api.nvim_win_is_valid(conf.win)
end

---@class minibuffer.core.SelectContext
---@field items any[]
---@field input string
---@field current_index integer 1-based; 0 means no selection
---@field selected_indicies integer[]
---@field multi boolean
---@field loading boolean

---@alias minibuffer.core.SelectFetchFn fun(input:string, cb:fun(items: any[]|nil, err:any|nil))
---@alias minibuffer.core.SelectFilterFn fun(ctx:minibuffer.core.SelectContext): any[]
---@alias minibuffer.core.SelectFooterFn fun(ctx:minibuffer.core.SelectContext): any[]
---@alias minibuffer.core.SelectCallback fun(selection: {item:any, index: integer}[])
---@alias minibuffer.core.SelectStartCallback fun(session: minibuffer.core.SelectSession, keyset: minibuffer.util.Keyset)

---@class minibuffer.core.SelectSession : minibuffer.core.Session
---@field prompt string
---@field max_height integer
---@field multi boolean
---@field dynamic_height boolean
---@field fetch_fn minibuffer.core.SelectFetchFn|nil
---@field filter_fn minibuffer.core.SelectFilterFn
---@field footer_fn minibuffer.core.SelectFooterFn|nil
---@field format_fn minibuffer.core.FormatFn
---@field on_start minibuffer.core.SelectStartCallback|nil
---@field on_select minibuffer.core.SelectCallback|nil
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil
---@field _closed boolean
---@field _entry { buf:integer|nil, win:integer|nil }
---@field _display { buf:integer|nil, win:integer|nil }
---@field _input string
---@field _items any[]
---@field _current_index integer 1-based; 0 means no selection
---@field _selected_indices integer[]
---@field _scroll_offset integer
---@field _loading boolean
---@field _fetch_generation integer
local SelectSession = {}
SelectSession.__index = SelectSession
SelectSession = SelectSession

---@class minibuffer.core.SelectSessionOpts
---@field resumable boolean|nil
---@field prompt string|nil
---@field max_height integer|nil
---@field multi boolean|nil
---@field dynamic_height boolean|nil
---@field fetch_fn minibuffer.core.SelectFetchFn
---@field filter_fn minibuffer.core.SelectFilterFn
---@field format_fn minibuffer.core.FormatFn
---@field footer_fn minibuffer.core.SelectFooterFn|nil
---@field on_start minibuffer.core.SelectStartCallback|nil
---@field on_select minibuffer.core.SelectCallback
---@field on_cancel minibuffer.core.CancelCallback|nil
---@field on_close minibuffer.core.CloseCallback|nil
---@field on_change minibuffer.core.ChangeCallback|nil

---@param opts minibuffer.core.SelectSessionOpts|nil
---@return minibuffer.core.SelectSession
function SelectSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    resumable = opts.resumable == true,
    prompt = opts.prompt or "Select: ",
    max_height = opts.max_height or 15,
    multi = opts.multi == true,
    dynamic_height = opts.dynamic_height == true,
    fetch_fn = opts.fetch_fn,
    filter_fn = opts.filter_fn,
    format_fn = opts.format_fn,
    footer_fn = opts.footer_fn or function(ctx)
      local prefix = ctx.multi and " C-x toggle, C-a toggle-all," or ""
      return {
        { #ctx.items .. " items", "Normal" },
        { prefix .. " C-y accept, C-n next, C-p prev", "Comment" },
      }
    end,
    on_start = opts.on_start,
    on_select = opts.on_select,
    on_cancel = opts.on_cancel,
    on_close = opts.on_close,
    on_change = opts.on_change,

    _closed = false,
    _entry = { buf = nil, win = nil },
    _display = { buf = nil, win = nil },
    _input = "",
    _items = {},
    _current_index = 1,
    _selected_indices = {},
    _scroll_offset = 0,
    _loading = false,
    _fetch_generation = 0,
  }, SelectSession)
  assert(self.fetch_fn ~= nil, "Must provide fetch_fn")
  assert(self.filter_fn ~= nil, "Must provide filter_fn")
  assert(self.format_fn ~= nil, "Must provide format_fn")

  return self
end

---@return minibuffer.core.SessionType
function SelectSession:type()
  return "select"
end

---@return boolean
function SelectSession:overridable()
  return true
end

function SelectSession:pre_start()
  local cmd_win = util.get_cmd_win()
  if not cmd_win then
    return
  end

  util.wipe_cmd_buffer()

  self._closed = false
  state.win_sizes = util.get_window_sizes()
  state.win_views = util.get_win_views()

  -- Setup display buffer and window
  local display_height = math.max(1, math.min(self.max_height, #self._items))
  self._display.buf = vim.api.nvim_create_buf(false, false)
  if self._display.buf == 0 then
    error("Failed to create display minibuffer")
  end
  local display_winopts = {
    relative = "editor",
    width = vim.o.columns,
    height = display_height,
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = vim.api.nvim_win_get_config(cmd_win).zindex + 2,
    border = { " ", "", " ", " ", " ", " ", " ", " " },
  }
  display_winopts.footer = self.footer_fn(self:get_ctx())
  display_winopts.footer_pos = "right"
  self._display.win = vim.api.nvim_open_win(self._display.buf, false, display_winopts)
  vim.api.nvim_win_call(self._display.win, function()
    vim.api.nvim_set_option_value("filetype", "", { scope = "local" })
    vim.api.nvim_set_option_value("eventignorewin", "all", { scope = "local" })
    vim.api.nvim_set_option_value("wrap", false, { scope = "local" })
    vim.api.nvim_set_option_value("linebreak", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
    vim.api.nvim_set_option_value("bufhidden", "hide", { scope = "local" })
    vim.api.nvim_set_option_value("buftype", "nofile", { scope = "local" })
    vim.api.nvim_set_option_value(
      "winhighlight",
      "NormalFloat:Normal,FloatBorder:Normal,FloatFooter:Normal",
      { scope = "local" }
    )
  end)

  -- Setup _entry buffer and window
  self._entry.buf = vim.api.nvim_create_buf(false, false)
  if self._entry.buf == 0 then
    error("Failed to create _entry minibuffer")
  end
  vim.bo[self._entry.buf].buftype = "prompt"
  vim.bo[self._entry.buf].complete = ""
  vim.fn.prompt_setprompt(self._entry.buf, self.prompt)
  vim.fn.prompt_setcallback(self._entry.buf, function(_)
    self:accept()
  end)
  self._entry.win = vim.api.nvim_open_win(self._entry.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = display_height + 1,
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = vim.api.nvim_win_get_config(cmd_win).zindex + 1,
    border = "none",
  })
  vim.wo[self._entry.win].wrap = false
  vim.wo[self._entry.win].winhighlight = "Normal:MinibufferPrompt"
end

function SelectSession:render()
  if self._closed then
    return
  end

  if not win_state_is_valid(self._entry) or not win_state_is_valid(self._display) then
    return
  end

  -- Calculate height based on the suggestions, loading state and max height
  local prev_display_height = vim.api.nvim_win_get_height(self._display.win)
  local total = #self._items
  local desired_height =
    math.max(1, math.min(self.max_height, total + (self._loading and 1 or 0)))
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

  vim.api.nvim_win_set_config(self._display.win, {
    footer = self.footer_fn(self:get_ctx()),
  })

  -- Set heights
  util.set_win_height(self._display.win, display_height)
  util.set_win_height(self._entry.win, display_height + 2)
  util.set_cmdheight(display_height + 2)
  util.resize_windows_for_cmdheight(
    state.win_sizes,
    display_height - util.get_ext().cmdheight
  )

  -- Build display output
  local start_idx = self._scroll_offset + 1
  local end_idx = math.min(total, start_idx + display_height - 1)
  local lines_data = {}
  for i = start_idx, end_idx do
    lines_data[#lines_data + 1] = self.format_fn(self._items[i])
  end
  if self._loading then
    lines_data[#lines_data + 1] =
      { { text = " … loading …", hl = "MinibufferLoading" } }
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

  -- Highlight current & multi selections (only if within visible items range)
  for _, i in ipairs(self._selected_indices) do
    if i ~= self._current_index and i >= start_idx and i <= end_idx then
      pcall(vim.api.nvim_buf_set_extmark, self._display.buf, state.ns, i - start_idx, 0, {
        line_hl_group = "MinibufferMultiSelected",
      })
    end
  end

  if self.on_change then
    pcall(self.on_change, self._input, self._items[self._current_index])
  end

  -- Force redraw
  vim.cmd.redraw()
end

function SelectSession:post_start()
  if self._closed then
    return
  end

  if not win_state_is_valid(self._entry) or not win_state_is_valid(self._display) then
    return
  end

  local keyset = util.create_condition_keyset(function()
    return state.session == self
  end, { buf = self._entry.buf, nowait = true, silent = true, noremap = true })

  keyset("i", "<Esc>", function()
    self:cancel()
  end)
  keyset("i", "<CR>", function()
    self:accept()
  end)
  keyset("i", "<C-y>", function()
    self:accept()
  end)
  keyset("i", "<Up>", function()
    self:move(-1)
  end)
  keyset("i", "<Down>", function()
    self:move(1)
  end)
  keyset("i", "<C-p>", function()
    self:move(-1)
  end)
  keyset("i", "<C-n>", function()
    self:move(1)
  end)
  keyset("i", "<S-Tab>", function()
    self:move(-1)
  end)
  keyset("i", "<Tab>", function()
    self:move(1)
  end)
  keyset("i", "<C-w>", "<C-S-w>")

  if self.multi then
    keyset("i", "<C-x>", function()
      self:toggle_selection()
    end)
    keyset("i", "<C-a>", function()
      self:toggle_selection_all()
    end)
  end

  if self.on_start then
    pcall(self.on_start, self, keyset)
  end
  state.active_window = util.focus_win(self._entry.win)

  vim.api.nvim_buf_attach(self._entry.buf, false, {
    on_lines = function(_, _, _, _, _, _, _)
      vim.api.nvim_set_option_value("modified", false, { buf = self._entry.buf })
      if self._closed then
        return true
      end
      local input = vim.fn.prompt_getinput(self._entry.buf)
      if input ~= self._input then
        self._input = input
        self:refresh_results()
      end
    end,
  })
  vim.api.nvim_win_call(self._entry.win, function()
    vim.cmd("startinsert")
  end)
  if self._input ~= "" then
    pcall(vim.api.nvim_feedkeys, self._input, "t", false)
  end
  vim.api.nvim_set_option_value("modified", false, { buf = self._entry.buf })

  if #self._items == 0 then
    self:refresh_results()
  end
end

function SelectSession:cancel()
  if self._closed then
    return
  end

  local cb = self.on_cancel
  self:close(function()
    if cb then
      vim.schedule(function()
        pcall(cb)
      end)
    end
  end)
end

function SelectSession:close(done)
  if self._closed then
    return
  end
  self._closed = true

  -- Invalidate any outstanding fetch requests
  self._fetch_generation = self._fetch_generation + 1

  local cleaned_up = false

  local function cleanup()
    if cleaned_up then
      return
    end
    cleaned_up = true
    vim.cmd("stopinsert")

    util.set_cmdheight()

    if self._display.win and vim.api.nvim_win_is_valid(self._display.win) then
      pcall(vim.api.nvim_win_close, self._display.win, true)
    end
    if self._display.buf and vim.api.nvim_buf_is_valid(self._display.buf) then
      pcall(vim.api.nvim_buf_delete, self._display.buf, { force = true })
    end
    self._display.win = nil
    self._display.buf = nil
    if self._entry.win and vim.api.nvim_win_is_valid(self._entry.win) then
      pcall(vim.api.nvim_win_close, self._entry.win, true)
    end
    if self._entry.buf and vim.api.nvim_buf_is_valid(self._entry.buf) then
      pcall(vim.api.nvim_buf_delete, self._entry.buf, { force = true })
    end
    self._entry.win = nil
    self._entry.buf = nil

    util.restore_window_sizes(state.win_sizes)
    util.restore_win_views(state.win_views)

    local active_win = state.active_window
    if active_win and vim.api.nvim_win_is_valid(active_win) then
      pcall(vim.api.nvim_set_current_win, active_win)
    end

    state.cleanup()

    if self.on_close then
      vim.schedule(function()
        pcall(self.on_close)
      end)
    end
    if done then
      vim.schedule(function()
        done()
      end)
    end
  end

  if vim.fn.mode():sub(1, 1) == "i" then
    -- Wait till leaving insert mode to ensure window restoration works properly
    vim.api.nvim_create_autocmd("InsertLeave", {
      once = true,
      callback = cleanup,
    })
    vim.cmd("stopinsert")
  else
    cleanup()
  end
end

function SelectSession:get_ctx()
  return {
    items = self._items,
    input = self._input,
    current_index = self._current_index,
    selected_indicies = self._selected_indices,
    multi = self.multi,
    loading = self._loading,
  }
end

function SelectSession:refresh_results()
  if self._closed then
    return
  end

  self._loading = true
  self._fetch_generation = self._fetch_generation + 1
  local generation = self._fetch_generation
  local ok, err = pcall(self.fetch_fn, self._input, function(items, err)
    -- discard stale
    if self._closed or generation ~= self._fetch_generation then
      return
    end
    if err then
      self._loading = false
      vim.schedule(function()
        self:render()
      end)
      return
    end

    self._items = items or {}
    self._items = self.filter_fn(self:get_ctx())
    if self.multi then
      self._selected_indices = {}
    end
    if #self._items == 0 then
      self._current_index = 0
      self._scroll_offset = 0
    else
      self._current_index = 1
      self._scroll_offset = 0
    end
    self._loading = false

    vim.schedule(function()
      self:render()
    end)
  end)

  if not ok then
    vim.notify("Failed to fetch data: " .. (type(err) == "string" and err or "ERROR"))
    return
  end
end

function SelectSession:accept()
  if self._closed then
    return
  end

  if #self._items == 0 or self._loading then
    return
  end

  local selection = {}
  if self.multi and #self._selected_indices > 0 then
    for _, i in ipairs(self._selected_indices) do
      if i <= #self._items then
        selection[#selection + 1] = { item = self._items[i], index = i }
      end
    end
  else
    if self._current_index <= 0 or self._current_index > #self._items then
      return
    end
    selection = { { item = self._items[self._current_index], index = 1 } }
  end

  local cb = self.on_select
  self:close(function()
    if cb then
      vim.schedule(function()
        pcall(cb, selection)
      end)
    end
  end)
end

---@param delta integer
function SelectSession:move(delta)
  if self._closed then
    return
  end

  local count = #self._items
  if count == 0 then
    return
  end

  self._current_index = ((self._current_index - 1 + delta) % count) + 1
  self:render()
end

---@param index integer
---@return boolean
function SelectSession:is_selected(index)
  if not self.multi then
    return false
  end
  for _, sel_idx in ipairs(self._selected_indices) do
    if sel_idx == index then
      return true
    end
  end
  return false
end

---@return any|nil
function SelectSession:get_selected()
  if self._current_index > 0 then
    return self._items[self._current_index]
  end
  return nil
end

function SelectSession:toggle_selection()
  if self._closed then
    return
  end

  if not self.multi or self._current_index == 0 or #self._items == 0 then
    return
  end
  local idx = self._current_index
  if self:is_selected(idx) then
    for i, sel_idx in ipairs(self._selected_indices) do
      if sel_idx == idx then
        table.remove(self._selected_indices, i)
        break
      end
    end
  else
    self._selected_indices[#self._selected_indices + 1] = idx
  end
  self:render()
end

function SelectSession:toggle_selection_all()
  if self._closed then
    return
  end

  if not self.multi or self._current_index == 0 or #self._items == 0 then
    return
  end
  if #self._items == #self._selected_indices then
    self._selected_indices = {}
  else
    self._selected_indices = {}
    for i = 1, #self._items do
      self._selected_indices[#self._selected_indices + 1] = i
    end
  end
  self:render()
end

return SelectSession
