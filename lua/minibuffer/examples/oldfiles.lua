local opts = { cwd = nil }

-- Collect recent files from v:oldfiles
local function gather_oldfiles()
  local files = vim.v.oldfiles or {}
  local items = {}

  for idx, path in ipairs(files) do
    if vim.fn.filereadable(path) == 1 then
      -- If cwd is set, only include files inside that directory
      if not opts.cwd or vim.startswith(path, vim.fn.fnamemodify(opts.cwd, ":p")) then
        items[#items + 1] = {
          index = idx,
          path = path,
          name = vim.fn.fnamemodify(path, ":t"),
        }
      end
    end
  end

  return items
end

local function format_fn(item)
  return {
    { text = "  " .. item.name, hl = "Normal" },
    { text = " - " .. item.path, hl = "Comment" },
  }
end

local function item_compare_fn(old, new)
  return old.path == new.path
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end
  local results = {}
  for _, item in ipairs(items) do
    if item:lower():find(input) then
      results[#results + 1] = item
    end
  end
  return results
end

return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  local oldfiles = gather_oldfiles()
  local minibuffer = require("minibuffer")
  minibuffer.select({
    resumable = true,
    prompt = "Oldfiles:",
    items = oldfiles,
    multi = false,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    item_compare_fn = item_compare_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
    end,
    on_start = function(buf, sess, keyset)
      -- Horizontal split open
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          sess:close()
          if item then
            vim.cmd("split " .. vim.fn.fnameescape(item.path))
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Vertical split open
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          sess:close()
          if item then
            vim.cmd("vsplit " .. vim.fn.fnameescape(item.path))
          end
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })
end
