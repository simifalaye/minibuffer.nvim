local state = require("minibuffer.state")
local util = require("minibuffer.util")
local ext = util.get_ext()

---@alias minibuffer.core.InputSubmitCallback fun(input:string)
---@alias minibuffer.core.InputGetSuggestionsFn fun(input:string, cursor_pos:integer): any[]
---@alias minibuffer.core.InputAcceptSuggestionFn fun(old_input:string, suggestion:string): new_input:string, new_cursor_pos:integer?
---@alias minibuffer.core.InputStartCallback fun(buf: integer, session: minibuffer.core.InputSession, keyset: minibuffer.util.Keyset)
---@alias minibuffer.core.InputFooterFn fun(items:any[]): any[]
---@alias minibuffer.core.AsyncInputSuggestionsFn fun(input:string, cursor_pos:integer, cb:fun(suggestions:any[]))

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
---@field footer_fn minibuffer.core.SelectFooterFn|nil
---@field enable_ts boolean
---@field display { buf:integer|nil, win:integer|nil, ns:integer|nil }
---@field suggestions any[]
---@field current_index integer
---@field cmd_bufopts table
---@field cmd_winopts table
---@field scroll_offset integer
---@field display_height integer
---@field display_height_prev integer
---@field loading boolean
---@field _req_id integer
local InputSession = {}
InputSession.__index = InputSession
InputSession = InputSession

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
---@field footer_fn minibuffer.core.SelectFooterFn|nil

---@param opts minibuffer.core.InputSessionOpts|nil
---@return minibuffer.core.InputSession
function InputSession.new(opts)
  opts = opts or {}
  assert(
    not (opts.get_suggestions and opts.async_get_suggestions),
    "get_suggestions and async_get_suggestions are mutually exclusive"
  )

  local self = setmetatable({
    resumable = opts.resumable == true,
    closed = false,
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
    footer_fn = opts.footer_fn or function(items)
      return {
        { #items .. " items", "Normal" },
        { " C-y accept, C-n next, C-p prev", "Comment" },
      }
    end,

    display = { buf = nil, win = nil, ns = nil },
    suggestions = {},
    current_index = 0,
    cmd_bufopts = {},
    cmd_winopts = {},
    scroll_offset = 0,
    display_height = 0,
    display_height_prev = 0,
    loading = false,
  }, InputSession)
  self._req_id = 0

  return self
end

---@return minibuffer.core.SessionType
function InputSession:type()
  return "input"
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
  state.win_sizes = util.get_window_sizes()
  state.win_views = util.get_win_views()

  self.cmd_bufopts = util.save_cmd_opts("buf", { "buftype", "complete" })
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].complete = ""
  self.cmd_winopts = util.save_cmd_opts("win", { "wrap" })
  vim.wo[win].wrap = false

  local display_height = math.min(self.max_height, #self.suggestions)
  display_height = math.max(display_height, 1)
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
    vim.api.nvim_set_option_value(
      "winhighlight",
      "NormalFloat:Normal,FloatBorder:Normal,FloatFooter:Normal",
      { scope = "local" }
    )
  end)

  self:refresh_suggestions()
end

function InputSession:render()
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
  util.resize_windows_for_cmdheight(state.win_sizes, self.display_height - ext.cmdheight)
  self.display_height_prev = self.display_height

  -- Build display output
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

  if self.on_change then
    pcall(self.on_change, self.input, self.suggestions[self.current_index])
  end

  -- Force redraw
  vim.cmd.redraw()
end

function InputSession:post_start()
  local buf = util.get_cmd_buf()
  local win = util.get_cmd_win()
  if not buf or not win then
    return
  end

  local base = { buffer = buf, nowait = true, silent = true, noremap = true }
  local keyset = util.create_condition_keyset(function()
    return state.session == self
  end)

  keyset("i", "<Esc>", function()
    self:cancel()
  end, base)
  keyset("i", "<C-c>", function()
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
  keyset("i", "<S-Tab>", function()
    self:move(-1)
  end, base)
  keyset("i", "<Tab>", function()
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
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
      vim.cmd("setlocal nomodified")
      if self.closed then
        return true
      end

      -- Get the input text and prompt length
      local input = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      input = input:sub(#self.prompt + 1)

      -- Refresh on change
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
  vim.api.nvim_set_option_value("modified", false, { buf = buf })
  pcall(vim.api.nvim_feedkeys, self.input, "t", false)
end

function InputSession:cancel()
  self:close()
  if self.on_cancel then
    pcall(self.on_cancel)
  end
end

function InputSession:close()
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
  state.cleanup()

  if self.on_close then
    pcall(self.on_close)
  end
end

function InputSession:set_input(text, pos)
  local buf = util.get_cmd_buf()
  if not buf then
    return
  end
  pos = pos or text:len()

  vim.api.nvim_buf_set_lines(buf, 0, 1, false, {
    self.prompt .. text,
  })
  vim.api.nvim_win_set_cursor(0, { 1, #self.prompt + pos })

  self.input = text
  self:refresh_suggestions()
end

function InputSession:refresh_suggestions()
  local win = util.get_cmd_win()
  if not win then
    return
  end

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

  -- 1-based position into `input`
  local cursor_pos = math.max(1, vim.api.nvim_win_get_cursor(win)[2] - #self.prompt + 1)

  if self.async_get_suggestions then
    self.loading = true
    self._req_id = self._req_id + 1
    local rid = self._req_id
    local ok = pcall(self.async_get_suggestions, self.input, cursor_pos, function(result)
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
      local ok, res = pcall(fn_get, self.input, cursor_pos)
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
  local newpos
  if cb then
    local ok, res, pos = pcall(cb, self.input, text)
    if not ok then
      return
    end
    newi = res
    newpos = pos
  else
    newi = self.input .. text
    newpos = newi:len()
  end

  self:set_input(newi, newpos)
end

---@param delta integer
function InputSession:move(delta)
  local count = #self.suggestions
  if count == 0 then
    return
  end

  self.current_index = ((self.current_index - 1 + delta) % count) + 1
  self:render()
end

function InputSession:submit()
  local final = self.input
  self:close()
  if self.on_submit then
    pcall(self.on_submit, final)
  end
end

return InputSession
