local function format_fn(item)
  return {
    { text = item, hl = "Normal" },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end
  return vim.fn.matchfuzzy(ctx.items, ctx.input)
end

---@class minibuffer.examples.GitFilesOpts
---@field cwd? string
---@field show_untracked? boolean

---@param opts? minibuffer.examples.GitFilesOpts
return function(opts)
  require("minibuffer.internal.guard").check()

  opts = vim.tbl_deep_extend("force", { cwd = nil }, opts or {})
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
    multi = true,
    dynamic_height = false,
    max_height = 15,
    fetch_fn = function(_, cb)
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
      }, function(res)
        if res.code ~= 0 then
          cb(nil, res.stderr)
          return
        end

        local items = vim.split(res.stdout or "", "\n", {
          trimempty = true,
        })
        cb(items)
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
