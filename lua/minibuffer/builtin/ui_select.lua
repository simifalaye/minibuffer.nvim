return function(items, opts, on_choice)
  local prompt = opts.prompt or "Select: "
  local format_item = opts.format_item or function(item)
    return " " .. item
  end
  vim.schedule(function()
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
        local item = result and result[1] or nil
        local item_idx = nil
        if item then
          for i, it in ipairs(items) do
            if it == item then
              item_idx = i
              break
            end
          end
        end
        on_choice(item, item_idx)
      end,
      on_cancel = function()
        on_choice(nil, nil)
      end,
      max_height = 20,
    })
  end)
end
