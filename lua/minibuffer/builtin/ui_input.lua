---@param opts? vim.ui.input.Opts Additional options. See |input()|
---@param on_confirm fun(input?: string)
return function(opts, on_confirm)
  require("minibuffer.internal.guard").check()

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
    fetch_fn = function(input, cb)
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
      cb(suggestions)
    end,
    ---@diagnostic disable-next-line: unused-local
    on_accept = function(ctx)
      return ctx.items[ctx.current_index]
    end,
    on_submit = function(ctx)
      on_confirm(ctx.input)
    end,
  })
end
