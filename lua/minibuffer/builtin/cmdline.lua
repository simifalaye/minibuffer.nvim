---@alias minibuffer.builtin.cmdline.CompletionType '"ex"' | '"comp"'

---@class minibuffer.builtin.cmdline.CompletionTypes
---@field EX '"ex"'
---@field COMP '"comp"'
---@field FILE '"file"'
local COMPLETION_TYPES = {
  EX = "ex",
  COMP = "comp",
}

---@class minibuffer.builtin.cmdline.Suggestion
---@field type minibuffer.builtin.cmdline.CompletionType
---@field value string

-- Get completion suggestions based on current input
local function get_suggestions(input)
  if not input or input == "" then
    return {} -- Empty table instead of placeholder suggestions
  end
  local input_list = vim.split(input, "|")
  local i = input_list[#input_list]

  local suggestions = {} ---@type minibuffer.builtin.cmdline.Suggestion[]

  local function map(list, type)
    if not list then
      return {}
    end
    return vim.tbl_map(function(item)
      return { type = type, value = item }
    end, list)
  end

  suggestions = vim.list_extend(
    suggestions,
    map(vim.fn.getcompletion(i, "command"), COMPLETION_TYPES.EX)
  )
  if #suggestions > 0 then
    return suggestions
  end

  -- Terminal takes a while to fetch completios, ignore it entirely
  if i:find("terminal") then
    return {}
  end

  suggestions = vim.list_extend(
    suggestions,
    map(vim.fn.getcompletion(i, "cmdline"), COMPLETION_TYPES.COMP)
  )

  return suggestions
end

-- Custom suggestion acceptance handler
local function on_accept_suggestion(q, suggestion)
  local words = vim.split(q, "%s+")
  local words_len = #words

  if words_len <= 1 then
    return suggestion.value
  end
  words[words_len] = suggestion.value
  return table.concat(words, " ")
end

-- Command input with Vim completion
return function()
  require("minibuffer").input({
    resumable = true,
    prompt = ":",
    initial_text = "",
    enable_ts = true,
    item_compare_fn = function(old, new)
      return old.value == new.value
    end,
    get_suggestions = get_suggestions,
    on_accept_suggestion = on_accept_suggestion,
    format_fn = function(item)
      if item.type == COMPLETION_TYPES.EX then
        return {
          { text = item.value, hl = "Function" },
          { text = " - Ex command", hl = "Comment" },
        }
      elseif item.type == COMPLETION_TYPES.COMP then
        return {
          { text = item.value, hl = "String" },
          { text = " - Completion", hl = "Comment" },
        }
      end
      return {}
    end,
    on_submit = function(command)
      if command ~= "" then
        vim.schedule(function()
          vim.fn.feedkeys(":" .. command .. "\r", "nx")
        end)
        vim.fn.histadd("cmd", command)
      end
    end,
  })
end
