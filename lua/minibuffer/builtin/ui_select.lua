return function(items, opts, on_choice)
  local prompt = opts.prompt or "Select:"
  local format_item = opts.format_item or function(item)
    return item
  end
  vim.schedule(function()
    require("minibuffer").select({
      prompt = prompt,
      items = items,
      item_compare_fn = function(old, new)
        return old == new
      end,
      format_fn = function(item)
        return { { text = format_item(item), hl = "Normal" } }
      end,
      filter_fn = function(current_items, input)
        input = input:lower()
        local out = {}
        for _, it in ipairs(current_items) do
          if it:find(input, 1, true) then
            out[#out + 1] = it
          end
        end
        return out
      end,
      on_select = function(result, idx)
        on_choice(result, idx)
      end,
      max_height = 20,
    })
  end)
end
