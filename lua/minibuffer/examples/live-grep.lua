---@class minibuffer.examples.LiveGrepOpts
---@field rg_opts string[]|nil
---@field cwd string|nil

if vim.fn.executable("rg") == 0 then
  vim.notify("rg is required for using the grep picker")
  return function() end
end

local util = require("minibuffer.util")

---@type minibuffer.examples.LiveGrepOpts
local opts = {
  rg_opts = {
    "rg",
    "--with-filename",
    "--line-number",
    "--column",
    "--no-heading",
    "--color=never",
    "--no-config",
    "--smart-case",
    "--hidden",
    "-g",
    "!**/.git/**",
  },
  cwd = nil,
}

local debounce = util.make_debounced(100)
local generation = 0
local current_proc ---@type vim.SystemObj?

local function parse_rg_line(line)
  -- rg format:
  -- file:line:column:text
  local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")

  if not file then
    return nil
  end

  return {
    file = file,
    line = tonumber(lnum),
    col = tonumber(col),
    text = text,
  }
end

local function format_fn(item)
  local prefix = string.format("%s:%d:%d: ", item.file, item.line, item.col)

  return {
    { text = prefix, hl = "Comment" },
    { text = item.text, hl = "Normal" },
  }
end

local function filter_fn(items, _)
  return items
end

local function async_fetch(input, cb)
  if input == "" then
    cb({})
    return
  end

  debounce(function()
    generation = generation + 1
    local current = generation

    local cmd = vim.list_extend({}, opts.rg_opts)

    cmd[#cmd + 1] = input

    if current_proc then
      current_proc:kill("sigterm")
      current_proc = nil
    end

    local system_opts = { text = true }

    if opts.cwd then
      system_opts.cwd = opts.cwd
    end

    current_proc = vim.system(cmd, system_opts, function(res)
      if current_proc then
        current_proc = nil
      end

      if current ~= generation then
        return
      end

      local out = {}

      if res.code == 0 and res.stdout then
        for _, line in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
          local item = parse_rg_line(line)
          if item then
            out[#out + 1] = item
          end
        end
      end

      cb(out)
    end)
  end)
end

---@param o minibuffer.examples.LiveGrepOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  require("minibuffer").select({
    resumable = true,
    prompt = "Grep: ",
    items = {},
    async_fetch = async_fetch,
    multi = true,
    allow_shrink = false,
    max_height = 18,
    format_fn = format_fn,
    filter_fn = filter_fn,

    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1]

        vim.cmd("edit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.file)))
        pcall(vim.api.nvim_win_set_cursor, 0, {
          item.line,
          item.col - 1,
        })
        vim.cmd("normal! zz")
        return
      end

      local qf = {}

      for _, item in ipairs(selection) do
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.file)),
          lnum = item.line,
          col = item.col,
          text = item.text,
        }
      end

      vim.fn.setqflist({}, " ", {
        title = "Grep Results",
        items = qf,
      })

      vim.cmd("copen")
    end,

    on_start = function(buf, sess, keyset)
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]

          if item then
            vim.cmd("split " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.file)))
            pcall(vim.api.nvim_win_set_cursor, 0, {
              item.line,
              item.col - 1,
            })
            vim.cmd("normal! zz")
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

          if item then
            vim.cmd("vsplit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.file)))
            pcall(vim.api.nvim_win_set_cursor, 0, {
              item.line,
              item.col - 1,
            })
            vim.cmd("normal! zz")
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
