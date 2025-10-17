return function(opts, on_confirm)
  local prompt = opts.prompt or "Enter: "
  local default = opts.default or ""
  local completion = opts.completion
  local highlight = opts.highlight or function(_)
    return "Normal"
  end
  vim.schedule(function()
    require("minibuffer").input({
      prompt = prompt,
      initial_text = default,
      item_compare_fn = function(old, new)
        return old == new
      end,
      format_fn = function(item)
        return { { text = item, hl = highlight(item) } }
      end,
      get_suggestions = function(input)
        local suggestions = {}

        local ok, completions = pcall(function()
          return vim.fn.getcompletion(input, completion)
        end)

        if ok and completions and #completions > 0 then
          for i = 1, math.min(15, #completions) do
            local comp = completions[i]
            table.insert(suggestions, comp)
          end
        end

        return suggestions
      end,
      on_accept_suggestion = function(input, suggestion)
        local words = vim.split(input, "%s+")
        local words_len = #words

        if words_len <= 1 then
          return suggestion .. " "
        end
        words[words_len] = suggestion
        return table.concat(words, " ") .. " "
      end,
      on_submit = function(input)
        on_confirm(input)
      end,
    })
  end)
end
