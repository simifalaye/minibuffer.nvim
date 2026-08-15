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

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  local names = {}
  local lookup = {}
  for _, item in ipairs(ctx.items) do
    names[#names + 1] = item.name
    lookup[item.name] = item
  end

  local matches = vim.fn.matchfuzzy(names, ctx.input)
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
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      cb(buffers)
    end,
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
        local item = selection[1].item
        if vim.api.nvim_buf_is_valid(item.bufnr) then
          vim.api.nvim_set_current_buf(item.bufnr)
        end
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = item.path ~= "" and item.path or item.name,
          text = "#" .. item.bufnr,
          lnum = 1,
          col = 1,
        }
      end
      vim.fn.setqflist({}, " ", { title = "Selected Buffers", items = qf })
      vim.cmd("copen")
    end,
    on_close = function()
      if active_win then
        update_preview_win(active_win, prev_buf)
      end
    end,
    on_start = function(sess, keyset)
      active_win = minibuffer.get_active_window()
      if not active_win then
        return
      end

      keyset("i", "<C-s>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("split " .. selected.bufnr)
              vim.api.nvim_set_current_buf(selected.bufnr)
            end)
          end
        end
      end)
      keyset("i", "<C-v>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("vsplit " .. selected.bufnr)
              vim.api.nvim_set_current_buf(selected.bufnr)
            end)
          end
        end
      end)
      keyset("i", "<C-d>", function()
        local selected = sess:get_selected()
        if selected then
          if selected and vim.api.nvim_buf_is_valid(selected.bufnr) then
            update_preview_win(active_win, get_replacement_buf(selected.bufnr))
            vim.api.nvim_buf_delete(selected.bufnr, {})

            -- Remove buffer from list
            local new_buffer_list = {}
            for _, item in ipairs(buffers) do
              if item.bufnr ~= selected.bufnr then
                new_buffer_list[#new_buffer_list + 1] = item
              end
            end
            buffers = new_buffer_list

            sess:refresh_results()
          end
        end
      end)
    end,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items", "Normal" },
        {
          " C-x toggle, C-a toggle-all, C-s split, C-v vsplit, C-d delete, C-y accept, C-n next, C-p prev",
          "Comment",
        },
      }
    end,
  })
end
