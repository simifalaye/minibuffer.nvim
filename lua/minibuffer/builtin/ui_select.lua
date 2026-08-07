---@generic T
---@param items T[] Arbitrary items
---@param opts vim.ui.select.Opts Options
---@param on_choice fun(item: T|nil, idx: integer|nil)
return function(items, opts, on_choice)
  local prompt = opts.prompt or "Select: "
  local format_item = opts.format_item or function(item)
    return item
  end
  require("minibuffer").select({
    prompt = prompt,
    items = items,
    format_fn = function(item)
      return { { text = format_item(item), hl = "Normal" } }
    end,
    filter_fn = function(current_items, input)
      input = input:lower()
      local out = {}
      for _, it in ipairs(current_items) do
        if format_item(it):lower():find(input, 1, true) then
          out[#out + 1] = it
        end
      end
      return out
    end,
    on_select = function(result, idx)
      on_choice(result[1], idx[1])
    end,
    on_cancel = function()
      on_choice(nil, nil)
    end,
    max_height = 20,
  })
end
