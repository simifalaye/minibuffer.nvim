---@class minibuffer.examples.GitFilesOpts
---@field cwd? string
---@field show_untracked? boolean

---@type minibuffer.examples.GitFilesOpts
local opts = {
  cwd = nil,
}

local function format_fn(item)
  return {
    { text = item, hl = "Normal" },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end
  return vim.fn.matchfuzzy(items, input)
end

---@param o? minibuffer.examples.GitFilesOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})
  local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ":p")
  local show_untracked = opts.show_untracked == true

  local git = vim
    .system({
      "git",
      "-C",
      cwd,
      "rev-parse",
      "--is-inside-work-tree",
    }, {
      text = true,
    })
    :wait()
  if git.code ~= 0 or vim.trim(git.stdout or "") ~= "true" then
    vim.notify(("Not a git repository: %s"):format(cwd), vim.log.levels.ERROR)
    return
  end

  require("minibuffer").select({
    resumable = true,
    prompt = "Git Files: ",
    items = {},
    multi = true,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    async_fetch = function(_, cb)
      local g_opts = {
        "git",
        "-C",
        cwd,
        "ls-files",
        "--cached",
        "--exclude-standard",
      }
      if show_untracked then
        table.insert(g_opts, "--others")
      end
      vim.system(g_opts, {
        text = true,
      }, function(result)
        if result.code ~= 0 then
          vim.schedule(function()
            cb({})
          end)
          return
        end

        local items = vim.split(result.stdout or "", "\n", {
          trimempty = true,
        })

        vim.schedule(function()
          cb(items)
        end)
      end)
    end,
    on_select = function(selection)
      if #selection == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(selection[1]))
        return
      end

      local qf = {}
      for _, item in ipairs(selection) do
        qf[#qf + 1] = {
          filename = item,
          lnum = 1,
          col = 1,
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
          vim.cmd("split " .. vim.fn.fnameescape(file))
        end
      end, {
        buffer = buf,
        noremap = true,
        silent = true,
      })
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local file = sess.filtered_items[sess.current_index]
          vim.cmd("vsplit " .. vim.fn.fnameescape(file))
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
