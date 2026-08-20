local state = require("minibuffer.state")
local util = require("minibuffer.util")

local cmdheight_autocmd_created = false

local M = {}

---@alias minibuffer.cmd.PopupItem any[]
---@alias minibuffer.cmd.PopupItems minibuffer.cmd.PopupItem[]

---@class minibuffer.cmd.State
---@field is_active boolean
---@field buf integer? Completion display buffer.
---@field win integer? Completion display window.
---@field mark integer? Selection extmark.
---@field items minibuffer.cmd.PopupItems
---@field selected integer Zero-based selected completion index, or -1 when nothing is selected.
---@field commands table<string, vim.api.keyset.command_info> Command info
---@field user_cmdheight integer The user configured cmdheight
---@field setting_cmdheight boolean Whether we are in the process of setting the cmdheight

---@type minibuffer.cmd.State
local s = {
  -- internal
  is_active = false,
  buf = nil,
  win = nil,
  mark = nil,
  items = {},
  selected = -1,
  commands = {},
  user_cmdheight = vim.o.cmdheight,
  setting_cmdheight = false,
}

---@return boolean
local function valid_buf()
  return s.buf ~= nil and vim.api.nvim_buf_is_valid(s.buf)
end

---@return boolean
local function valid_win()
  return s.win ~= nil and vim.api.nvim_win_is_valid(s.win)
end

---Reset transient completion state.
---@return nil
local function reset_state()
  s.items = {}
  s.selected = -1
  s.mark = nil
end

---Destroy the completion display window and its buffer.
---@return nil
local function destroy_window()
  if valid_win() then
    local _, _ = pcall(vim.api.nvim_win_close, s.win, true)
  end
  if valid_buf() then
    local _, _ = pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
  end

  s.win = nil
  s.buf = nil
  s.mark = nil
end

--- Set cmdheight without modifying the internal stored cmdheight
--- while still allowing any other OptionSet autocmds to run
---@param value integer
local function set_cmdheight(value)
  if vim.o.cmdheight == value then
    return
  end

  s.setting_cmdheight = true
  local ok, err = xpcall(function()
    vim.o.cmdheight = value
  end, debug.traceback)
  s.setting_cmdheight = false

  if not ok then
    error(err)
  end
end

---Set the completion display height and corresponding command-line height.
---@param height integer Completion display height.
---@return nil
local function set_height(height)
  if not valid_win() then
    return
  end

  if height == 0 then
    vim.api.nvim_win_set_config(s.win, {
      hide = true,
      height = 1,
    })
  elseif vim.api.nvim_win_get_height(s.win) ~= height then
    vim.api.nvim_win_set_config(s.win, {
      hide = false,
      height = height,
    })
  end

  set_cmdheight(height + 1)
end

---Add command descriptions to completion items.
---
---Only command-name completion is enriched. If the completion already
---contains an `info` field, it is left unchanged.
---@param items minibuffer.cmd.PopupItems
---@return minibuffer.cmd.PopupItems
local function enrich_items(items)
  if vim.fn.getcmdtype() ~= ":" then
    return items
  end

  local cmdline = vim.fn.getcmdline()

  -- Only enrich the initial command name. Once there is whitespace,
  -- we are completing an argument rather than the command itself.
  if cmdline:match("^%s*%S+%s") then
    return items
  end

  for _, item in ipairs(items) do
    local word = item[1]
    if word and word ~= "" and (item[4] == nil or item[4] == "") then
      local command = s.commands[word]
      if command and command.definition then
        item[4] = command.definition
      end
    end
  end

  return items
end

---Format a single completion item for display.
---@param item minibuffer.cmd.PopupItem
---@return table[] Highlighted line data.
local function format_item(item)
  local word = item[1] or ""
  local menu = item[3] or ""
  local info = item[4] or ""

  local line = {
    {
      text = " " .. word,
      hl = "Normal",
    },
  }
  if menu ~= "" then
    line[#line + 1] = {
      text = " - " .. menu,
      hl = "Comment",
    }
  elseif info ~= "" then
    line[#line + 1] = {
      text = " - " .. info,
      hl = "Comment",
    }
  end

  return line
end

---Render the current completion popup.
---@return nil
local function render()
  if not s.is_active or not valid_win() or not valid_buf() then
    return
  end

  local count = #s.items
  if count == 0 then
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, {})
    vim.api.nvim_buf_clear_namespace(s.buf, state.ns, 0, -1)

    set_height(0)
    return
  end

  local conf = require("minibuffer.config").get()
  local max_height = conf.cmd.max_height or 15
  local dynamic_height = conf.cmd.dynamic_height == true
  local height = math.min(max_height, count)
  if not dynamic_height then
    height = math.max(vim.api.nvim_win_get_height(s.win), height)
  end

  set_height(height)

  local lines = {}
  for _, item in ipairs(s.items) do
    lines[#lines + 1] = format_item(item)
  end
  util.write_highlighted_lines(s.buf, state.ns, lines)

  if s.selected >= 0 and s.selected < count then
    pcall(
      vim.api.nvim_buf_set_extmark,
      s.buf,
      state.ns,
      s.selected,
      0,
      { line_hl_group = "MinibufferSelection" }
    )
  end

  vim.cmd.redraw()
end

---Handle a `vim.ui_attach()` event.
---@param event string UI event name.
---@param ... any Event-specific arguments.
---@return nil
local function on_event(event, ...)
  if not s.is_active then
    return
  end

  if event == "popupmenu_show" then
    local items, selected = ...

    s.items = enrich_items(items)
    s.selected = selected
    render()
  elseif event == "popupmenu_select" then
    s.selected = ...
    if s.selected < 0 or not valid_buf() then
      return
    end

    if s.mark then
      vim.api.nvim_buf_del_extmark(s.buf, state.ns, s.mark)
    end

    s.mark = vim.api.nvim_buf_set_extmark(
      s.buf,
      state.ns,
      s.selected,
      0,
      { line_hl_group = "MinibufferSelection" }
    )
  elseif event == "popupmenu_hide" then
    local conf = require("minibuffer.config").get()
    if conf.cmd.autotrigger then
      return
    end
    s.items = {}
    s.selected = -1
    render()
  end
end

---Create the completion display window.
---@return boolean success Whether the window was created.
local function create_window()
  local cmd_win = util.get_cmd_win()
  if not cmd_win then
    return false
  end

  s.buf = vim.api.nvim_create_buf(false, true)

  s.win = vim.api.nvim_open_win(s.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = 1,
    row = vim.o.lines - 1,
    col = 0,
    style = "minimal",
    border = "none",
    hide = true,
    zindex = vim.api.nvim_win_get_config(cmd_win).zindex + 1,
  })

  vim.api.nvim_win_call(s.win, function()
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

  return true
end

---Enable the custom command-line completion popup.
---@return nil
function M.enable()
  local conf = require("minibuffer.config").get()
  if not conf or not conf.cmd or not conf.cmd.enabled then
    return
  end

  if not cmdheight_autocmd_created then
    vim.api.nvim_create_autocmd("OptionSet", {
      group = state.augroup,
      pattern = { "cmdheight" },
      callback = function(_)
        if not s.setting_cmdheight then
          s.user_cmdheight = vim.v.option_new
        end
      end,
    })
  end

  if s.is_active then
    return
  end

  s.commands = vim.api.nvim_get_commands({ builtin = false }) -- TODO: use true when implemented

  if not create_window() then
    return
  end

  s.is_active = true

  vim.ui_attach(state.ns, {
    ext_popupmenu = true,
  }, on_event)

  if conf.cmd.autotrigger then
    ---Accept the current completion and immediately trigger the next one.
    vim.keymap.set("c", "<C-y>", function()
      if vim.fn.wildmenumode() == 0 then
        return "<C-y>"
      end

      vim.api.nvim_feedkeys(vim.keycode("<C-y>"), "n", false)

      vim.schedule(function()
        if s.is_active and vim.fn.mode() == "c" then
          vim.fn.wildtrigger()
        end
      end)

      return ""
    end, {
      expr = true,
      nowait = true,
      silent = true,
      noremap = true,
    })
  end
end

---Disable the custom command-line completion popup.
---@return nil
function M.disable()
  if not s.is_active then
    return
  end

  s.is_active = false

  vim.ui_detach(state.ns)

  local _, _ = pcall(vim.keymap.del, "c", "<C-y>")

  destroy_window()

  reset_state()

  vim.schedule(function()
    set_cmdheight(s.user_cmdheight)
  end)
end

---Check whether the custom completion popup is is active.
---@return boolean
function M.is_active()
  return s.is_active
end

return M
