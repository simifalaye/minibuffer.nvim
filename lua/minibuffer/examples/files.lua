if vim.fn.executable("rg") == 0 then
  vim.notify("rg is required for using the files picker")
  return function() end
end

local util = require("minibuffer.internal.util")

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
local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end

  return vim.fn.matchfuzzy(ctx.items, ctx.input)
end

-- Load all files once using rg
local function load_files(opts, cb)
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
    if res.code ~= 0 then
      cb(nil, res.stderr)
      return
    end

    loaded_cwd = opts.cwd
    cb(vim.split(res.stdout, "\n", { trimempty = true }))
  end)
end

---@class minibuffer.examples.FilesGrepOpts
---@field rg_opts string[]|nil
---@field cwd string|nil

---@param opts minibuffer.examples.FilesGrepOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  ---@type minibuffer.examples.FilesGrepOpts
  local default_opts = {
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
  opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  opts.cwd = opts.cwd and vim.fn.fnamemodify(opts.cwd, ":p")

  all_files = {}
  loaded_cwd = nil
  require("minibuffer").select({
    resumable = true,
    prompt = "Files: ",
    multi = true,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
      debounce(function()
        load_files(opts, cb)
      end)
    end,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        vim.cmd("edit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item)))
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(opts.cwd, item),
          lnum = 1,
          col = 1,
        }
      end

      vim.fn.setqflist({}, " ", { title = "Selected Files", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      keyset("i", "<C-s>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd("split " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected)))
            end)
          end
        end
      end)
      keyset("i", "<C-v>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd(
                "vsplit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected))
              )
            end)
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
