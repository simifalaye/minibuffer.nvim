---@param opts? vim.ui.input.Opts Additional options. See |input()|
---@param on_confirm fun(input?: string)
return function(opts, on_confirm)
  opts = opts or {}
  local prompt = opts.prompt or "Enter: "
  local default = opts.default or ""
  local completion = opts.completion or ""
  local highlight = opts.highlight or function(_)
    return "Normal"
  end
  require("minibuffer").input({
    prompt = prompt,
    initial_text = default,
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
    ---@diagnostic disable-next-line: unused-local
    on_accept_suggestion = function(input, suggestion)
      return suggestion
    end,
    on_submit = function(input)
      on_confirm(input)
    end,
  })
end
