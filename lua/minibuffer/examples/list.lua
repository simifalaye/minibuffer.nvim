---@class minibuffer.examples.ListOpts
---@field type? "quickfix"|"loclist"

---@type minibuffer.examples.ListOpts
local opts = {
  type = "quickfix",
}

local function gather_items(kind)
  local list = kind == "loclist" and vim.fn.getloclist(0) or vim.fn.getqflist()
  local items = {}
  for _, entry in ipairs(list) do
    if entry.valid == 1 then
      local file = entry.bufnr > 0 and vim.api.nvim_buf_get_name(entry.bufnr)
        or entry.filename
        or ""
      items[#items + 1] = {
        bufnr = entry.bufnr,
        file = file,
        lnum = entry.lnum,
        col = entry.col,
        text = entry.text or "",
      }
    end
  end
  return items
end

local function format_fn(item)
  return {
    {
      text = vim.fn.fnamemodify(item.file, ":."),
      hl = "Comment",
    },
    {
      text = ":" .. item.lnum,
      hl = "Number",
    },
    {
      text = ":" .. item.col,
      hl = "Number",
    },
    {
      text = "  " .. item.text,
      hl = "Normal",
    },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end

  local lookup = {}
  local keys = {}
  for _, item in ipairs(items) do
    local key = table.concat({
      item.file,
      tostring(item.lnum),
      item.text,
    }, " ")

    keys[#keys + 1] = key
    lookup[key] = item
  end

  local matches = vim.fn.matchfuzzy(keys, input)
  local results = {}
  for _, key in ipairs(matches) do
    results[#results + 1] = lookup[key]
  end

  return results
end

---@param o? minibuffer.examples.ListOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  require("minibuffer").select({
    resumable = true,
    prompt = opts.type == "loclist" and "Location List: " or "Quickfix List: ",
    items = gather_items(opts.type),
    multi = false,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      local item = selection[1]
      if not item then
        return
      end
      vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      vim.api.nvim_win_set_cursor(0, {
        item.lnum,
        math.max(item.col - 1, 0),
      })
      vim.cmd("normal! zvzz")
    end,
  })
end
