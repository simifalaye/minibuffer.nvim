local function create_preview(win)
  -- Save current window state
  local cur_buf = vim.api.nvim_win_get_buf(win)

  -- Create scratch buffer
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, scratch)

  return scratch,
    function()
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(cur_buf) then
        vim.api.nvim_win_set_buf(win, cur_buf)
      end
    end
end

local function update_preview(scratch, win, buf)
  local win_height = vim.api.nvim_win_get_height(win)
  local lcount = vim.api.nvim_buf_line_count(buf)

  -- Get last known position mark
  local mark = vim.api.nvim_buf_get_mark(buf, '"')
  local cursor_line = mark[1] > 0 and mark[1] <= lcount and mark[1] or 1

  -- Compute range around that line
  local half = math.floor(win_height / 2)
  local start_line = math.max(0, cursor_line - half - 1) -- 0-indexed
  local end_line = math.min(lcount, start_line + win_height)

  -- Get lines
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
  if #lines == 0 then
    lines = { "[Empty buffer]" }
  end

  -- Write into scratch buffer
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)

  -- Match filetype
  local ft = vim.bo[buf].filetype
  if ft ~= "" then
    vim.bo[scratch].filetype = ft
  end
end

-- Collect listed & loaded buffers (excluding special/unlisted)
local function gather_buffers()
  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  local items = {}

  for _, info in ipairs(bufs) do
    if info.loaded == 1 then
      local name = info.name ~= "" and info.name or "[No Name]"
      items[#items + 1] = {
        bufnr = info.bufnr,
        name = name,
        lastused = info.lastused or 0,
        changed = info.changed,
      }
    end
  end

  -- Sort by most recently used (descending)
  table.sort(items, function(a, b)
    return a.lastused > b.lastused
  end)

  return items
end

local function format_fn(item)
  local display = string.format("%d  %s", item.bufnr, item.name)
  return {
    { text = item.changed == 1 and "+ " or "  ", hl = "Changed" },
    { text = display, hl = "Normal" },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end
  local results = {}
  for _, item in ipairs(items) do
    if item.name:lower():find(input) then
      results[#results + 1] = item
    end
  end
  return results
end

return function()
  local active_win
  local buffers = gather_buffers()
  local preview_buffer, restore_fn
  local minibuffer = require("minibuffer")
  minibuffer.select({
    resumable = true,
    prompt = "Buffers:",
    items = buffers,
    multi = false,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_change = function(_, item)
      if not active_win then
        return
      end
      if not preview_buffer then
        preview_buffer, restore_fn = create_preview(active_win)
      end
      vim.schedule(function()
        if item then
          update_preview(preview_buffer, active_win, item.bufnr)
        end
      end)
    end,
    on_select = function(selection)
      if selection[1].bufnr then
        vim.cmd("b " .. selection[1].bufnr)
      end
    end,
    on_close = function()
      if restore_fn then
        restore_fn()
      end
      if preview_buffer and vim.api.nvim_buf_is_valid(preview_buffer) then
        vim.api.nvim_buf_delete(preview_buffer, { force = true })
      end
    end,
    on_start = function(buf, sess, keyset)
      active_win = minibuffer.get_active_window()
      if not active_win then
        return
      end

      -- Horizontal split open
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          sess:close()
          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            vim.cmd("split")
            vim.api.nvim_set_current_buf(item.bufnr)
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Vertical split open
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          sess:close()
          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            vim.cmd("vsplit")
            vim.api.nvim_set_current_buf(item.bufnr)
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Delete buffer
      keyset("i", "<C-d>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          if item and vim.api.nvim_buf_is_valid(item.bufnr) then
            vim.cmd("bdelete " .. item.bufnr)
            -- Refresh buffer list after deletion
            sess.items = gather_buffers()
            sess.filtered_items = filter_fn(sess.items, sess.input)
            if #sess.filtered_items == 0 then
              sess.current_index = 0
            else
              sess.current_index = math.min(sess.current_index, #sess.filtered_items)
            end
            sess:render()
          end
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })
end
