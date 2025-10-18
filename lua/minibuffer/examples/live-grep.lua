if vim.fn.executable("rg") == 0 then
  vim.notify("rg is required for using the files picker")
  return function() end
end

local opts = {
  rg_opts = {
    "rg",
    "--with-filename",
    "--line-number",
    "--no-heading",
    "--color=never",
    "--no-config",
    "--smart-case",
    "--max-columns=300",
    "--max-columns-preview",
    "--colors=path:none",
    "--colors=line:none",
    "--colors=match:fg:red",
    "--colors=match:style:nobold",
    "-g=!**/.git/**",
  },
  cwd = nil,
}

local util = require("minibuffer.util")

local debounce = util.make_debounced(100)

-- Each grep item stored as table
-- { file=string, line=number, col=number|nil, text=string }
local function format_fn(item)
  local prefix = string.format("%s:%d: ", item.file, item.line)
  return {
    { text = prefix, hl = "Comment" },
    { text = item.text, hl = "Normal" },
  }
end

-- Use rg's filtering entirely
local function filter_fn(items, _)
  return items
end

-- Async fetch using rg
local function async_fetch(input, cb)
  if input == "" then
    cb({})
    return
  end

  debounce(function()
    local cmd = vim.deepcopy(opts.rg_opts)
    cmd = vim.list_extend(cmd, { input })
    if opts.cwd then
      cmd = vim.list_extend(cmd, { opts.cwd })
    end
    if vim.system then
      vim.system(cmd, { text = true }, function(res)
        local out = {}
        if res.code == 0 and res.stdout and res.stdout ~= "" then
          for _, line in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
            local file, lnum, text = line:match("([^:]+):(%d+):(.*)")
            if file and lnum and text then
              out[#out + 1] = {
                file = file,
                line = tonumber(lnum),
                col = 1,
                text = text,
              }
            end
          end
        end
        cb(out)
      end)
    else
      local collected = {}
      local job = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          for _, l in ipairs(data) do
            local file, lnum, text = l:match("([^:]+):(%d+):(.*)")
            if file and lnum and text then
              collected[#collected + 1] = {
                file = file,
                line = tonumber(lnum),
                col = 1,
                text = text,
              }
            end
          end
        end,
        on_exit = function(_, code)
          if code ~= 0 then
            collected = {}
          end
          vim.schedule(function()
            cb(collected)
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
    prompt = "Grep:",
    items = {},
    async_fetch = async_fetch,
    multi = true,
    allow_shrink = false,
    max_height = 18,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      local function jump(item)
        if not item then
          return
        end
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        pcall(vim.api.nvim_win_set_cursor, 0, { item.line, 0 })
        vim.cmd("normal! zz")
      end
      if type(selection) == "table" and selection[1] and selection[1].file then
        -- Multi selection -> jump to first match
        jump(selection[1])
      elseif selection and selection.file then
        jump(selection)
      end
    end,
    on_start = function(buf, sess, keyset)
      -- Open current match in horizontal split
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          if item then
            vim.cmd("split " .. vim.fn.fnameescape(item.file))
            pcall(vim.api.nvim_win_set_cursor, 0, { item.line, 0 })
            vim.cmd("normal! zz")
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Open current match in vertical split
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          if item then
            vim.cmd("vsplit " .. vim.fn.fnameescape(item.file))
            pcall(vim.api.nvim_win_set_cursor, 0, { item.line, 0 })
            vim.cmd("normal! zz")
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Send matches to quickfix list (selected ones if any, else current)
      keyset("i", "<C-q>", function()
        local indices = (#sess.selected_indices > 0) and sess.selected_indices
          or { sess.current_index }
        local qf = {}
        for _, i in ipairs(indices) do
          local it = sess.filtered_items[i]
          if it then
            qf[#qf + 1] = {
              filename = it.file,
              lnum = it.line,
              col = it.col or 1,
              text = it.text,
            }
          end
        end
        if #qf > 0 then
          vim.fn.setqflist(qf, " ", { title = "Grep Results" })
          vim.cmd("copen")
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })
end
