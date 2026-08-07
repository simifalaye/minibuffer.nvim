local state = require("minibuffer.state")
local util = require("minibuffer.util")
local ext = util.get_ext()

---@alias minibuffer.core.SelectFilterFn fun(items:any[], input:string): any[]
---@alias minibuffer.core.SelectCallback fun(items:any[], idx:integer|integer[])
---@alias minibuffer.core.SelectStartCallback fun(buf: integer, session: minibuffer.core.SelectSession, keyset: minibuffer.util.Keyset)
---@alias minibuffer.core.SelectFooterFn fun(items:any[]): any[]
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
---@field footer_fn minibuffer.core.SelectFooterFn|nil
---@field display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field input string
---@field filtered_items any[]
---@field current_index integer
---@field selected_indices integer[]
---@field cmd_bufopts table
---@field cmd_winopts table
---@field scroll_offset integer
---@field display_height integer
---@field display_height_prev integer
---@field loading boolean
---@field _req_id integer
local SelectSession = {}
SelectSession.__index = SelectSession
SelectSession = SelectSession

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
---@field footer_fn minibuffer.core.SelectFooterFn|nil

---@param opts minibuffer.core.SelectSessionOpts|nil
---@return minibuffer.core.SelectSession
function SelectSession.new(opts)
  opts = opts or {}
  local self = setmetatable({
    closed = false,
    resumable = opts.resumable == true,
    prompt = opts.prompt or "Select: ",
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
    footer_fn = opts.footer_fn or function(items)
      local prefix = opts.multi and " C-x toggle, C-a toggle-all," or ""
      return {
        { #items .. " items", "Normal" },
        { prefix .. " C-y accept, C-n next, C-p prev", "Comment" },
      }
    end,

    display = { buf = nil, win = nil, ns = nil },
    input = "",
    filtered_items = opts.items or {},
    current_index = 1,
    selected_indices = {},
    cmd_bufopts = {},
    cmd_winopts = {},
    scroll_offset = 0,
    display_height = 0,
    display_height_prev = 0,
    loading = false,
  }, SelectSession)
  self._req_id = 0

  return self
end

---@return minibuffer.core.SessionType
function SelectSession:type()
  return "select"
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

  self.closed = false
  state.win_sizes = util.get_window_sizes()
  state.win_views = util.get_win_views()

  self.cmd_bufopts = util.save_cmd_opts("buf", { "buftype", "complete" })
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].complete = ""
  self.cmd_winopts = util.save_cmd_opts("win", { "wrap" })
  vim.wo[win].wrap = false

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

  local winopts = {
    relative = "editor",
    width = vim.o.columns,
    height = display_height,
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    zindex = 999,
    border = { " ", "", " ", " ", " ", " ", " ", " " },
  }
  winopts.footer = self.footer_fn(self.filtered_items)
  winopts.footer_pos = "right"
  self.display.buf = vim.api.nvim_create_buf(false, false)
  self.display.win = vim.api.nvim_open_win(self.display.buf, false, winopts)
  vim.api.nvim_win_call(self.display.win, function()
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

  self:update_filter()
end

function SelectSession:render()
  if not self.display.buf then
    return
  end

  local win = util.get_cmd_win()
  if not win then
    return
  end

  -- Calculate height based on the suggestions, loading state and max height
  local total = #self.filtered_items
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

  vim.api.nvim_win_set_config(self.display.win, {
    footer = self.footer_fn(self.filtered_items),
  })

  -- Set heights
  util.set_win_height(self.display.win, self.display_height, false)
  util.set_win_height(win, self.display_height + 2, true)
  util.resize_windows_for_cmdheight(state.win_sizes, self.display_height - ext.cmdheight)
  self.display_height_prev = self.display_height

  -- Build display output
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

  if self.on_change then
    pcall(self.on_change, self.input, self.filtered_items[self.current_index])
  end

  -- Force redraw
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
  keyset("i", "<S-Tab>", function()
    self:move(-1)
  end, base)
  keyset("i", "<Tab>", function()
    self:move(1)
  end, base)
  keyset("i", "<C-w>", "<C-S-w>", base)

  if self.multi then
    keyset("i", "<C-x>", function()
      self:toggle_selection()
    end, base)
    keyset("i", "<C-a>", function()
      self:toggle_selection_all()
    end, base)
  end

  if self.on_start then
    pcall(self.on_start, buf, self, keyset)
  end
  state.active_window = util.focus_cmd_win()

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _, _, _, _, _, _)
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
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
  vim.api.nvim_set_option_value("modified", false, { buf = buf })
  pcall(vim.api.nvim_feedkeys, self.input, "t", false)
end

function SelectSession:cancel()
  self:close()
  if self.on_cancel then
    pcall(self.on_cancel)
  end
end

function SelectSession:close()
  if self.closed then
    return
  end
  self.closed = true

  -- Stop insert mode and force redraw before switching back to old window
  vim.cmd("stopinsert")
  vim.cmd.redraw()

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
  local row, col = unpack(vim.api.nvim_win_get_cursor(state.active_window))
  vim.api.nvim_win_set_cursor(state.active_window, { row, col + 1 })

  state.cleanup()

  if self.on_close then
    pcall(self.on_close)
  end
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

  self:close()
  if self.on_select then
    pcall(self.on_select, result, idx)
  end
end

---@param delta integer
function SelectSession:move(delta)
  local count = #self.filtered_items
  if count == 0 then
    return
  end

  self.current_index = ((self.current_index - 1 + delta) % count) + 1
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

function SelectSession:toggle_selection_all()
  if not self.multi or self.current_index == 0 or #self.filtered_items == 0 then
    return
  end
  if #self.filtered_items == #self.selected_indices then
    self.selected_indices = {}
  else
    self.selected_indices = vim.tbl_keys(self.filtered_items)
  end
  self:render()
end

return SelectSession
