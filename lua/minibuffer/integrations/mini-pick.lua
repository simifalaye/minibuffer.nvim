local M = {}

local set_items_cb = nil
local active = false

local function expand_callable(x, ...)
  if vim.is_callable(x) then
    return x(...)
  end
  return x
end

local function item_to_string(item)
  item = expand_callable(item)
  if type(item) == "string" then
    return item
  end
  if type(item) == "table" and type(item.text) == "string" then
    return item.text
  end
  return vim.inspect(item, { newline = " ", indent = "" })
end

function M.is_picker_active()
  return active
end

function M.set_picker_items(items, _)
  if set_items_cb then
    set_items_cb(items)
    set_items_cb = nil
  end
end

function M.start(opts)
  set_items_cb = nil
  active = false

  local pick = require("mini.pick")
  local match = opts.source.match or pick.default_match
  local choose = opts.source.choose or pick.default_choose
  local choose_marked = opts.source.choose_marked or pick.default_choose_marked
  require("minibuffer").select({
    resumable = true,
    prompt = opts.source.name .. ":",
    items = {},
    async_fetch = function(_, cb)
      if not opts.source.items then
        return
      end
      if type(opts.source.items) == "table" then
        cb(opts.source.items)
      elseif type(opts.source.items) == "function" then
        active = true
        set_items_cb = cb
        opts.source.items()
      end
    end,
    multi = true, -- allow multi selection
    allow_shrink = false,
    max_height = 15,
    format_fn = function(item)
      return {
        { text = " " .. item_to_string(item), hl = "Normal" },
      }
    end,
    filter_fn = function(items, input)
      local keys = {}
      local idx = 1
      local stritems = vim.tbl_map(function(i)
        keys[#keys + 1] = idx
        idx = idx + 1
        return item_to_string(i)
      end, items)
      local indices = match(stritems, keys, { input }, { sync = true }) or {}
      if #indices > 0 then
        return vim.tbl_map(function(i)
          return stritems[i]
        end, indices)
      end
      return {}
    end,
    on_select = function(items)
      if #items == 1 then
        choose(items[1])
      elseif #items > 1 then
        choose_marked(items, {})
      end
    end,
    on_close = function()
      active = false
    end,
  })
end

return M
