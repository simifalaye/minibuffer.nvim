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
    fetch_fn = function(_, cb)
      cb(items)
    end,
    format_fn = function(item)
      return { { text = format_item(item), hl = "Normal" } }
    end,
    filter_fn = function(ctx)
      local input = ctx.input:lower()
      local out = {}
      for _, it in ipairs(ctx.items) do
        if format_item(it):lower():find(input, 1, true) then
          out[#out + 1] = it
        end
      end
      return out
    end,
    on_select = function(selection)
      if #selection < 1 then
        return
      end
      local selected = selection[1]
      on_choice(selected.item, selected.index)
    end,
    on_cancel = function()
      on_choice(nil, nil)
    end,
    max_height = 20,
  })
end
