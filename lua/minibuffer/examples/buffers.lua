local function update_preview_win(win, buf)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
  end
end

-- Collect listed & loaded buffers (excluding special/unlisted)
local function gather_buffers()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  local items = {}
  for _, info in ipairs(bufs) do
    if info.loaded == 1 then
      local path = info.name
      local name = path ~= "" and vim.fn.fnamemodify(path, ":t") or "[No Name]"
      items[#items + 1] = {
        bufnr = info.bufnr,
        path = path,
        name = name,
        lastused = info.lastused or 0,
        changed = info.changed,
      }
    end
  end

  table.sort(items, function(a, b)
    return a.lastused > b.lastused
  end)

  return items
end

local bufnr_max_width = 4
local bufnr_overflow_str = "999+"

local function format_fn(item)
  local bufnr_str = tostring(item.bufnr)
  local bufnr_len = #bufnr_str

  if bufnr_len > bufnr_max_width then
    bufnr_str = bufnr_overflow_str
  else
    bufnr_str = bufnr_str .. string.rep(" ", bufnr_max_width - bufnr_len)
  end

  return {
    { text = bufnr_str, hl = "Normal" },
    { text = item.changed == 1 and " * " or "   ", hl = "Changed" },
    { text = item.name, hl = "Normal" },
    {
      text = item.path ~= "" and ("  " .. item.path) or "",
      hl = "Comment",
    },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end

  local names = {}
  local lookup = {}
  for _, item in ipairs(items) do
    names[#names + 1] = item.name
    lookup[item.name] = item
  end

  local matches = vim.fn.matchfuzzy(names, input)
  local results = {}

  for _, name in ipairs(matches) do
    results[#results + 1] = lookup[name]
  end

  return results
end

local function get_replacement_buf(current)
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= current and info.loaded == 1 then
      return info.bufnr
    end
  end
  return vim.api.nvim_create_buf(false, true)
end

local function remove_buffer(items, bufnr)
  local result = {}
  for _, item in ipairs(items) do
    if item.bufnr ~= bufnr then
      result[#result + 1] = item
    end
  end
  return result
end

return function()
  local active_win
  local buffers = gather_buffers()
  local minibuffer = require("minibuffer")
  local prev_buf = vim.api.nvim_get_current_buf()

  minibuffer.select({
    resumable = true,
    prompt = "Buffers: ",
    items = buffers,
    multi = true,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_change = function(_, item)
      if not active_win then
        return
      end
      if item and vim.api.nvim_buf_is_valid(item.bufnr) then
        update_preview_win(active_win, item.bufnr)
      end
    end,
    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1]
        if vim.api.nvim_buf_is_valid(item.bufnr) then
          vim.api.nvim_set_current_buf(item.bufnr)
        end
        return
      end

      local qf = {}
      for _, item in ipairs(selection) do
        qf[#qf + 1] = {
          filename = item.path ~= "" and item.path or item.name,
          text = "#" .. item.bufnr,
        }
      end
      vim.fn.setqflist({}, " ", {
        title = "Selected Buffers",
        items = qf,
        lnum = 1,
        col = 1,
      })
      vim.cmd("copen")
    end,
    on_close = function()
      if active_win then
        update_preview_win(active_win, prev_buf)
      end
    end,
    on_start = function(buf, sess, keyset)
      active_win = minibuffer.get_active_window()
      if not active_win then
        return
      end

      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]

          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            sess:close()

            vim.cmd("split")
            vim.api.nvim_set_current_buf(item.bufnr)
          end
        end
      end, {
        buffer = buf,
        noremap = true,
        silent = true,
      })
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]

          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            sess:close()

            vim.cmd("vsplit")
            vim.api.nvim_set_current_buf(item.bufnr)
          end
        end
      end, {
        buffer = buf,
        noremap = true,
        silent = true,
      })
      keyset("i", "<C-d>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]

          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            update_preview_win(active_win, get_replacement_buf(item.bufnr))
            vim.api.nvim_buf_delete(item.bufnr, {})

            sess.items = remove_buffer(sess.items, item.bufnr)
            sess.filtered_items = filter_fn(sess.items, sess.input)
            if #sess.filtered_items == 0 then
              sess.current_index = 0
            else
              sess.current_index = math.min(sess.current_index, #sess.filtered_items)
            end
            sess:render()
          end
        end
      end, {
        buffer = buf,
        noremap = true,
        silent = true,
      })
    end,
    footer_fn = function(items)
      return {
        { #items .. " items", "Normal" },
        {
          " C-x toggle, C-a toggle-all, C-s split, C-v vsplit, C-d delete, C-y accept, C-n next, C-p prev",
          "Comment",
        },
      }
    end,
  })
end
