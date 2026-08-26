local function gather_history(kind)
  local histtype = kind == "search" and "/" or ":"
  local items = {}

  -- Newest first
  for i = vim.fn.histnr(histtype), 1, -1 do
    local value = vim.fn.histget(histtype, i)
    if value ~= "" then
      items[#items + 1] = {
        text = value,
      }
    end
  end

  return items
end

local function format_fn(item)
  return {
    { text = item.text, hl = "Normal" },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local texts = {}
  local lookup = {}

  for _, item in ipairs(ctx.items) do
    texts[#texts + 1] = item.text
    lookup[item.text] = item
  end

  local matches = vim.fn.matchfuzzy(texts, ctx.input)

  local results = {}
  for _, text in ipairs(matches) do
    results[#results + 1] = lookup[text]
  end

  return results
end

---@class minibuffer.builtin.HistoryOpts
---@field type? "cmd"|"search"

---@param opts? minibuffer.builtin.HistoryOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = vim.tbl_deep_extend("force", { type = nil }, opts or {})
  local items = gather_history(opts.type)

  require("minibuffer").select({
    resumable = true,
    prompt = opts.type == "search" and "Search History: " or "Command History: ",
    multi = false,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(items)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      local item = selection[1].item
      if not item then
        return
      end

      if opts.type == "cmd" then
        -- Put the command into the command line for editing.
        vim.fn.feedkeys(":" .. item.text, "n")
      else
        -- Execute the search.
        vim.fn.setreg("/", item.text)
        vim.cmd("normal! n")
      end
    end,
  })
end
