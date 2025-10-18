---@class PickerItem
---@field text string
---@field path string

local state = {
  ---@class FFFPickerState
  ---@field current_file_cache string
  state = {},
  ns_id = vim.api.nvim_create_namespace("MiniPick FFFiles Picker"),
}

---@param query string|nil
---@return PickerItem[]
local function find(query)
  local file_picker = require("fff.file_picker")

  query = query or ""
  local fff_result =
    file_picker.search_files(query, 100, 4, state.current_file_cache, false)

  local items = {}
  for _, fff_item in ipairs(fff_result) do
    local item = {
      text = fff_item.relative_path,
      path = fff_item.path,
    }
    table.insert(items, item)
  end

  return items
end

return function()
  -- Setup fff.nvim
  local file_picker = require("fff.file_picker")
  if not file_picker.is_initialized() then
    local setup_success = file_picker.setup()
    if not setup_success then
      vim.notify("Could not setup fff.nvim", vim.log.levels.ERROR)
      return
    end
  end

  -- Cache current file to deprioritize in fff.nvim
  if not state.current_file_cache then
    local current_buf = vim.api.nvim_get_current_buf()
    if current_buf and vim.api.nvim_buf_is_valid(current_buf) then
      local current_file = vim.api.nvim_buf_get_name(current_buf)
      if current_file ~= "" and vim.fn.filereadable(current_file) == 1 then
        local relative_path = vim.fs.relpath(vim.uv.cwd() or "", current_file)
        state.current_file_cache = relative_path
      else
        state.current_file_cache = nil
      end
    end
  end

  require("minibuffer").select({
    resumable = true,
    prompt = "Files:",
    items = {}, -- empty initially; async_fetch fills
    async_fetch = function(input, cb)
      cb(find(input))
    end,
    multi = true, -- allow multi selection
    allow_shrink = false,
    max_height = 15,
    format_fn = function(item)
      return {
        { text = " " .. item.text, hl = "Normal" },
        { text = ": " .. item.path, hl = "Comment" },
      }
    end,
    filter_fn = function(items)
      return items
    end,
    on_select = function(selection)
      for _, file in ipairs(selection) do
        vim.cmd("edit " .. vim.fn.fnameescape(file.path))
      end
    end,
    on_start = function(buf, sess, keyset)
      -- Open current highlighted file in horizontal split
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local file = sess.filtered_items[sess.current_index]
          vim.cmd("split " .. vim.fn.fnameescape(file))
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Open current highlighted file in vertical split
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local file = sess.filtered_items[sess.current_index]
          vim.cmd("vsplit " .. vim.fn.fnameescape(file))
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Send selection(s) to quickfix list
      keyset("i", "<C-q>", function()
        local qf = {}
        local indices = (#sess.selected_indices > 0) and sess.selected_indices
          or { sess.current_index }
        for _, i in ipairs(indices) do
          local file = sess.filtered_items[i]
          if file then
            qf[#qf + 1] = { filename = file, lnum = 1, col = 1, text = file }
          end
        end
        if #qf > 0 then
          vim.fn.setqflist(qf, " ", { title = "Selected Files" })
          vim.cmd("copen")
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })

  state.current_file_cache = nil -- Reset cache
end
