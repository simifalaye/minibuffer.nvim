---@class minibuffer.examples.HistoryOpts
---@field type? "cmd"|"search"

---@type minibuffer.examples.HistoryOpts
local opts = {
  type = "cmd",
}

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

local function filter_fn(items, input)
  if input == "" then
    return items
  end

  local texts = {}
  local lookup = {}

  for _, item in ipairs(items) do
    texts[#texts + 1] = item.text
    lookup[item.text] = item
  end

  local matches = vim.fn.matchfuzzy(texts, input)

  local results = {}
  for _, text in ipairs(matches) do
    results[#results + 1] = lookup[text]
  end

  return results
end

---@param o? minibuffer.examples.HistoryOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  local items = gather_history(opts.type)
  require("minibuffer").select({
    resumable = true,
    prompt = opts.type == "search" and "Search History: " or "Command History: ",
    items = items,
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
