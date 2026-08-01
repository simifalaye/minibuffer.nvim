---@alias minibuffer.builtin.cmdline.CompletionType '"ex"' | '"comp"'

---@class minibuffer.builtin.cmdline.CompletionTypes
---@field EX '"ex"'
---@field COMP '"comp"'
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
---@param allow_shrink boolean
return function(allow_shrink)
  require("minibuffer").input({
    resumable = true,
    prompt = ":",
    initial_text = "",
    enable_ts = true,
    get_suggestions = get_suggestions,
    on_accept_suggestion = on_accept_suggestion,
    allow_shrink = allow_shrink or false,
    format_fn = function(item)
      if item.type == COMPLETION_TYPES.EX then
        return {
          { text = " " .. item.value, hl = "Function" },
          { text = " - Ex command", hl = "Comment" },
        }
      elseif item.type == COMPLETION_TYPES.COMP then
        return {
          { text = " " .. item.value, hl = "String" },
          { text = " - Completion", hl = "Comment" },
        }
      end
      return {}
    end,
    on_start = function(buf, sess, keyset)
      local hist_idx = vim.fn.histnr("cmd") + 1
      local save_input

      local function prev_cmd()
        if not save_input then
          save_input = sess.input
        end
        if hist_idx > 1 then
          hist_idx = hist_idx - 1
        end
        return vim.fn.histget("cmd", hist_idx)
      end

      local function next_cmd()
        if not save_input then
          save_input = sess.input
        end
        local last = vim.fn.histnr("cmd")
        if hist_idx < last then
          hist_idx = hist_idx + 1
        else
          local input = save_input
          save_input = nil
          return input
        end
        return vim.fn.histget("cmd", hist_idx)
      end

      -- Navigate history
      keyset("i", "<C-k>", function()
        sess:set_input(prev_cmd())
      end, { buffer = buf, noremap = true, silent = true })
      keyset("i", "<C-j>", function()
        sess:set_input(next_cmd())
      end, { buffer = buf, noremap = true, silent = true })
    end,
    on_submit = function(command)
      if command ~= "" then
        vim.schedule(function()
          local ok, err = pcall(vim.fn.feedkeys, ":" .. command .. "\r", "nx")
          if not ok then
            vim.api.nvim_echo({
              { err, "ErrorMsg" },
            }, true, {})
          end
        end)
        vim.fn.histadd("cmd", command)
      end
    end,
  }, true)
end
