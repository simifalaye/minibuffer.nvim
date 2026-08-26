local ok, fff = pcall(require, "fff")
if not ok then
  error("Make sure fff.nvim is installed and loaded.")
end
if not fff.file_search then
  error("Your version of fff.nvim is missing the `file_search` api. Can't proceed.")
end

local function toggle_value(current, values)
  for i, value in ipairs(values) do
    if value == current then
      return values[(i % #values) + 1]
    end
  end
  return values[1]
end

local M = {}

---@class minibuffer.integrations.FFFindOpts
---@field cwd string?
---@field mode 'files'|'directories'|'mixed'|nil
---@field max_results integer?
---@field max_threads integer?
---@field show_score boolean?

--- Run fff file search
---@param opts minibuffer.integrations.FFFindOpts
function M.file_search(opts)
  require("minibuffer.internal.guard").check()

  local current_file
  local win = vim.api.nvim_get_current_win()
  if win and vim.api.nvim_win_is_valid(win) then
    local buf = vim.api.nvim_win_get_buf(win)
    current_file = vim.api.nvim_buf_get_name(buf)
  end

  opts = vim.tbl_deep_extend("force", {
    cwd = vim.fn.getcwd(),
    mode = "files",
    max_results = 100,
    max_threads = 4,
    show_score = true,
  }, opts or {})
  opts.cwd = vim.fn.fnamemodify(opts.cwd, ":p"):gsub("(.)/$", "%1")

  require("minibuffer").select({
    resumable = true,
    prompt = "FFFiles: ",
    fetch_fn = function(input, cb)
      local result = fff.file_search(input, {
        mode = opts.mode,
        max_results = opts.max_results,
        current_file = current_file, -- path to deprioritize for distance scoring
        max_threads = opts.max_threads,
        cwd = opts.cwd,
      })
      cb(result.items)
    end,
    multi = true,
    dynamic_height = false,
    max_height = 15,
    format_fn = function(item)
      if not item then
        return {}
      end
      local data = { { text = item.relative_path, hl = "Normal" } }
      if opts.show_score and item.total_frecency_score then
        table.insert(data, { text = ": " .. item.total_frecency_score, hl = "Comment" })
      end
      return data
    end,
    filter_fn = function(ctx)
      return vim.tbl_filter(function(item)
        return item.relative_path and item.relative_path:len() > 0
      end, ctx.items)
    end,
    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        vim.cmd("edit " .. vim.fn.fnameescape(item.relative_path))
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = item.relative_path,
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
          sess:close(function()
            vim.cmd(
              "split "
                .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected.relative_path))
            )
          end)
        end
      end)
      keyset("i", "<C-v>", function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "vsplit "
                .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected.relative_path))
            )
          end)
        end
      end)
      keyset("i", "<C-t>", function()
        opts.mode = toggle_value(opts.mode, { "files", "directories", "mixed" })
        sess:refresh_results()
        sess:render()
      end)
    end,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items, " .. opts.mode .. " mode", "Normal" },
        {
          " C-x toggle, C-a toggle-all, C-t toggle-mode, C-a toggle-all, C-y accept, C-n next, C-p prev",
          "Comment",
        },
      }
    end,
  })
end

---@class minibuffer.integrations.FFFGrepOpts
---@field cwd string|nil
---@field mode 'plain'|'regex'|'fuzzy'|nil
---@field smart_case boolean|nil

--- Run fff grep
---@param opts minibuffer.integrations.FFFGrepOpts
function M.content_search(opts)
  require("minibuffer.internal.guard").check()

  opts = vim.tbl_deep_extend("force", {
    cwd = vim.fn.getcwd(),
    mode = "regex",
    smart_case = true,
  }, opts or {})
  opts.cwd = vim.fn.fnamemodify(opts.cwd, ":p"):gsub("(.)/$", "%1")

  require("minibuffer").select({
    resumable = true,
    prompt = "FFFGrep: ",
    fetch_fn = function(input, cb)
      local result = require("fff").content_search(input, {
        mode = opts.mode,
        cwd = opts.cwd,
      })
      cb(result.items)
    end,
    multi = true,
    dynamic_height = false,
    max_height = 15,
    format_fn = function(item)
      if not item then
        return {}
      end
      return {
        { text = item.relative_path, hl = "Normal" },
        { text = ": " .. item.line_content, hl = "Comment" },
      }
    end,
    filter_fn = function(ctx)
      return vim.tbl_filter(function(item)
        return item.relative_path and item.relative_path:len() > 0 and item.line_number
      end, ctx.items)
    end,
    on_select = function(selection)
      if #selection == 1 then
        local item = selection[1].item
        vim.cmd("edit " .. vim.fn.fnameescape(item.relative_path))
        pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, 0 })
        vim.cmd("normal! zz")
        return
      end

      local qf = {}
      for _, selected in ipairs(selection) do
        local item = selected.item
        qf[#qf + 1] = {
          filename = item.relative_path,
          lnum = item.line_number,
          col = item.col or 1,
          text = item.line_content,
        }
      end
      vim.fn.setqflist({}, " ", { title = "Grep Results", items = qf })
      vim.cmd("copen")
    end,
    on_start = function(sess, keyset)
      keyset("i", "<C-s>", function()
        local selected = sess:get_selected()
        if selected then
          sess:close(function()
            vim.cmd(
              "split "
                .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected.relative_path))
            )
            pcall(vim.api.nvim_win_set_cursor, 0, { selected.line_number, 0 })
            vim.cmd("normal! zz")
          end)
        end
      end)
      keyset("i", "<C-v>", function()
        local selected = sess:get_selected()
        if selected then
          if selected then
            sess:close(function()
              vim.cmd(
                "vsplit "
                  .. vim.fs.joinpath(opts.cwd, vim.fn.fnameescape(selected.relative_path))
              )
              pcall(vim.api.nvim_win_set_cursor, 0, { selected.line_number, 0 })
              vim.cmd("normal! zz")
            end)
          end
        end
      end)
      keyset("i", "<C-t>", function()
        opts.mode = toggle_value(opts.mode, { "plain", "regex", "fuzzy" })
        sess:refresh_results()
        sess:render()
      end)
    end,
    footer_fn = function(ctx)
      return {
        { #ctx.items .. " items, " .. opts.mode .. " mode", "Normal" },
        {
          " C-x toggle, C-a toggle-all, C-t toggle-mode, C-a toggle-all, C-y accept, C-n next, C-p prev",
          "Comment",
        },
      }
    end,
  })
end

return M
