---@class minibuffer.examples.OldfilesOpts
---@field cwd string|nil

---@class minibuffer.examples.OldfilesOpts
local opts = {
  cwd = nil,
}

local function is_in_cwd(path, cwd)
  return vim.fs.relpath(cwd, path) ~= nil
end

local function gather_oldfiles(cwd)
  local files = vim.v.oldfiles or {}
  local items = {}

  cwd = cwd and vim.fn.fnamemodify(cwd, ":p")
  for _, path in ipairs(files) do
    path = vim.fn.fnamemodify(path, ":p")
    if vim.fn.filereadable(path) == 1 then
      if not cwd or is_in_cwd(path, cwd) then
        items[#items + 1] = {
          path = path,
          name = vim.fn.fnamemodify(path, ":t"),
        }
      end
    end
  end

  return items
end

local function format_fn(item)
  local dir = vim.fn.fnamemodify(item.path, ":h")
  return {
    { text = item.name, hl = "Normal" },
    { text = "  " .. dir, hl = "Comment" },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end

  local paths = {}
  local lookup = {}

  for _, item in ipairs(items) do
    paths[#paths + 1] = item.path
    lookup[item.path] = item
  end
  local matches = vim.fn.matchfuzzy(paths, input)

  local results = {}
  for _, path in ipairs(matches) do
    results[#results + 1] = lookup[path]
  end

  return results
end

---@param o minibuffer.examples.OldfilesOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  local oldfiles = gather_oldfiles(opts.cwd)

  require("minibuffer").select({
    resumable = true,
    prompt = "Oldfiles: ",
    items = oldfiles,
    multi = true,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1]
        vim.cmd("edit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.path)))
        vim.cmd('normal! g`"')
        return
      end

      local qf = {}
      for _, item in ipairs(selection) do
        qf[#qf + 1] = {
          filename = vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.path)),
          lnum = 1,
          col = 1,
        }
      end

      vim.fn.setqflist({}, " ", {
        title = "Selected Oldfiles",
        items = qf,
      })
      vim.cmd("copen")
    end,
    on_start = function(buf, sess, keyset)
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]

          if item then
            sess:close()

            vim.cmd("split " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.path)))
            vim.cmd('normal! g`"')
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
            sess:close()
            vim.cmd("vsplit " .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(item.path)))
            vim.cmd('normal! g`"')
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
