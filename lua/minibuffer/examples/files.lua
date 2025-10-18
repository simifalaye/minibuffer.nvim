if vim.fn.executable("fd") == 0 then
  vim.notify("fd is required for using the files picker")
  return function() end
end

local util = require("minibuffer.util")

local opts = {
  fd_opts = { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git", "-p" },
  cwd = nil,
}

local debounce = util.make_debounced(50)

-- Format each file path: directory part in Comment, filename normal
local function format_fn(item)
  local name = item:match("([^/]+)$") or item
  local dir = item:sub(1, #item - #name)
  return {
    { text = " " .. dir, hl = "Comment" },
    { text = name, hl = "Normal" },
  }
end

-- Use fd's filtering entirely
local function filter_fn(items, _)
  return items
end

-- Async fetch using fd
local function async_fetch(input, cb)
  debounce(function()
    local cmd = vim.deepcopy(opts.fd_opts)
    if opts.cwd then
      cmd = vim.list_extend(cmd, { "--base-directory", opts.cwd })
    end
    if input ~= "" then
      -- Let fd narrow by pattern; still filtered again locally.
      cmd[#cmd + 1] = input
    end

    if vim.system then
      vim.system(cmd, { text = true }, function(res)
        local files = {}
        if res.code == 0 and res.stdout and res.stdout ~= "" then
          files = vim.split(res.stdout, "\n", { trimempty = true })
        end
        cb(files)
      end)
    else
      local out = {}
      local job = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then
              out[#out + 1] = line
            end
          end
        end,
        on_exit = function(_, code)
          if code ~= 0 then
            out = {}
          end
          vim.schedule(function()
            cb(out)
          end)
        end,
      })
      if job <= 0 then
        cb({})
      end
    end
  end)
end

return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})
  require("minibuffer").select({
    resumable = true,
    prompt = "Files:",
    items = {}, -- empty initially; async_fetch fills
    async_fetch = async_fetch,
    multi = true, -- allow multi selection
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      for _, file in ipairs(selection) do
        vim.cmd("edit " .. vim.fn.fnameescape(file))
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
end
