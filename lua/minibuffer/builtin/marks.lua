---@class minibuffer.builtin.Mark
---@field mark string
---@field file string
---@field lnum integer
---@field col integer
---@field text string

local function gather_marks()
  local seen = {}
  local items = {}

  local function add_marks(list)
    for _, mark in ipairs(list) do
      if mark.pos[2] > 0 and not seen[mark.mark] then
        seen[mark.mark] = true

        local file = mark.file ~= "" and mark.file
          or vim.api.nvim_buf_get_name(mark.pos[1])
        local line = vim.fn.getbufline(file, mark.pos[2])[1] or ""
        items[#items + 1] = {
          mark = mark.mark:sub(2), -- a, A, 0, ...
          file = file,
          lnum = mark.pos[2],
          col = mark.pos[3],
          text = vim.trim(line),
        }
      end
    end
  end

  add_marks(vim.fn.getmarklist())
  add_marks(vim.fn.getmarklist(vim.api.nvim_get_current_buf()))

  return items
end

local function format_fn(item)
  return {
    { text = item.mark, hl = "Identifier" },
    { text = "  " .. vim.fn.fnamemodify(item.file, ":."), hl = "Comment" },
    { text = ":" .. item.lnum, hl = "Number" },
    { text = "  " .. item.text, hl = "Normal" },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local lookup = {}
  local keys = {}
  for _, item in ipairs(ctx.items) do
    local key = table.concat({
      item.mark,
      item.file,
      item.text,
    }, " ")
    keys[#keys + 1] = key
    lookup[key] = item
  end

  local matches = vim.fn.matchfuzzy(keys, ctx.input)
  local results = {}
  for _, key in ipairs(matches) do
    results[#results + 1] = lookup[key]
  end

  return results
end

return function()
  require("minibuffer.internal.guard").check()

  local marks = gather_marks()
  require("minibuffer").select({
    resumable = true,
    prompt = "Marks: ",
    multi = false,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(marks)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      local item = selection[1].item
      if not item then
        return
      end
      vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
      vim.cmd("normal! zvzz")
    end,
  })
end
