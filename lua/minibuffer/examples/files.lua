---@class minibuffer.examples.FilesGrepOpts
---@field rg_opts string[]|nil
---@field cwd string|nil

if vim.fn.executable("rg") == 0 then
  vim.notify("rg is required for using the files picker")
  return function() end
end

local util = require("minibuffer.util")

---@type minibuffer.examples.FilesGrepOpts
local opts = {
  rg_opts = {
    "rg",
    "--files",
    "--hidden",
    "--color",
    "never",
    "-g",
    "!.git",
  },
  cwd = nil,
}

local debounce = util.make_debounced(50)

local all_files = {} ---@type string[]
local loading = false
local loaded_cwd = nil

-- Format each file path: directory part in Comment, filename normal
local function format_fn(item)
  local name = item:match("([^/]+)$") or item
  local dir = item:sub(1, #item - #name)

  return {
    { text = dir, hl = "Comment" },
    { text = name, hl = "Normal" },
  }
end

-- Use vim's fuzzy matcher
local function filter_fn(items, input)
  if input == "" then
    return items
  end

  return vim.fn.matchfuzzy(items, input)
end

-- Load all files once using rg
local function load_files(cb)
  if loading then
    return
  end

  if #all_files > 0 and loaded_cwd == opts.cwd then
    cb(all_files)
    return
  end

  loading = true

  local cmd = vim.list_extend({}, opts.rg_opts)
  local proc_opts = { text = true }
  if opts.cwd then
    proc_opts.cwd = opts.cwd
  end

  vim.system(cmd, proc_opts, function(res)
    loading = false
    if res.code ~= 0 or not res.stdout then
      all_files = {}
    else
      all_files = vim.split(res.stdout, "\n", { trimempty = true })
    end
    loaded_cwd = opts.cwd
    cb(all_files)
  end)
end

local function async_fetch(_, cb)
  debounce(function()
    load_files(function(files)
      cb(files)
    end)
  end)
end

---@param o minibuffer.examples.FilesGrepOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  all_files = {}
  loaded_cwd = nil
  require("minibuffer").select({
    resumable = true,
    prompt = "Files: ",
    items = {},
    async_fetch = async_fetch,
    multi = true,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      if #selection == 1 then
        vim.cmd("edit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selection[1])))
        return
      end

      local qf = {}
      for _, item in ipairs(selection) do
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(opts.cwd, item),
        }
      end

      vim.fn.setqflist({}, " ", {
        title = "Selected Files",
        items = qf,
        lnum = 1,
        col = 1,
      })
      vim.cmd("copen")
    end,
    on_start = function(buf, sess, keyset)
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local file = sess.filtered_items[sess.current_index]
          vim.cmd("split " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(file)))
        end
      end, {
        buffer = buf,
        noremap = true,
        silent = true,
      })
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local file = sess.filtered_items[sess.current_index]
          vim.cmd("vsplit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(file)))
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
