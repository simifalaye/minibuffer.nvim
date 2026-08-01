local ok, fff = pcall(require, "fff")
if not ok then
  error("Make sure fff.nvim is installed and loaded.")
end
if not fff.file_search then
  error("Your version of fff.nvim is missing the `file_search` api. Can't proceed.")
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
    items = {}, -- empty initially; async_fetch fills
    async_fetch = function(input, cb)
      local result = fff.file_search(input, {
        mode = opts.mode,
        max_results = opts.max_results,
        current_file = current_file, -- path to deprioritize for distance scoring
        max_threads = opts.max_threads,
        cwd = opts.cwd,
      })
      cb(result.items)
    end,
    multi = true, -- allow multi selection
    allow_shrink = false,
    max_height = 15,
    format_fn = function(item)
      local data = { { text = " " .. item.relative_path, hl = "Normal" } }
      if opts.show_score then
        table.insert(data, { text = ": " .. item.total_frecency_score, hl = "Comment" })
      end
      return data
    end,
    filter_fn = function(items)
      return items
    end,
    on_select = function(selection)
      for _, item in ipairs(selection) do
        vim.cmd("edit " .. vim.fn.fnameescape(item.relative_path))
      end
    end,
    on_start = function(buf, sess, keyset)
      -- Open current highlighted file in horizontal split
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          sess:close()
          local item = sess.filtered_items[sess.current_index]
          vim.cmd("split " .. vim.fn.fnameescape(item.relative_path))
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Open current highlighted file in vertical split
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          sess:close()
          local item = sess.filtered_items[sess.current_index]
          vim.cmd("vsplit " .. vim.fn.fnameescape(item.relative_path))
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Send selection(s) to quickfix list
      keyset("i", "<C-q>", function()
        local qf = {}
        local indices = (#sess.selected_indices > 0) and sess.selected_indices
          or { sess.current_index }
        for _, i in ipairs(indices) do
          local item = sess.filtered_items[i]
          if item then
            qf[#qf + 1] = {
              filename = item.relative_path,
              lnum = 1,
              col = 1,
              text = item.relative_path,
            }
          end
        end
        if #qf > 0 then
          sess:close()
          vim.fn.setqflist({}, " ", { title = "Selected Files", items = qf })
          vim.cmd("copen")
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })
end

---@class minibuffer.integrations.FFFGrepOpts
---@field cwd string?
---@field mode 'plain'|'regex'|'fuzzy'|nil

--- Run fff grep
---@param opts minibuffer.integrations.FFFGrepOpts
function M.content_search(opts)
  opts = vim.tbl_deep_extend("force", {
    cwd = vim.fn.getcwd(),
    mode = "plain",
  }, opts or {})
  opts.cwd = vim.fn.fnamemodify(opts.cwd, ":p"):gsub("(.)/$", "%1")

  require("minibuffer").select({
    resumable = true,
    prompt = "FFFGrep:",
    items = {}, -- empty initially; async_fetch fills
    async_fetch = function(input, cb)
      local result = require("fff").content_search(input, {
        mode = opts.mode,
        cwd = opts.cwd,
      })
      cb(result.items)
    end,
    multi = true,
    allow_shrink = false,
    max_height = 15,
    format_fn = function(item)
      return {
        { text = " " .. item.relative_path, hl = "Normal" },
        { text = ": " .. item.line_content, hl = "Comment" },
      }
    end,
    filter_fn = function(items)
      return items
    end,
    on_select = function(selection)
      local function jump(item)
        if not item then
          return
        end
        vim.cmd("edit " .. vim.fn.fnameescape(item.relative_path))
        pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, 0 })
        vim.cmd("normal! zz")
      end
      if type(selection) == "table" and selection[1] and selection[1].relative_path then
        jump(selection[1])
      end
    end,
    on_start = function(buf, sess, keyset)
      -- Open current match in horizontal split
      keyset("i", "<C-s>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          if item then
            sess:close()
            vim.cmd("split " .. vim.fn.fnameescape(item.relative_path))
            pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, 0 })
            vim.cmd("normal! zz")
          end
        end
      end, { buffer = buf, noremap = true, silent = true })

      -- Open current match in vertical split
      keyset("i", "<C-v>", function()
        if sess.current_index > 0 then
          local item = sess.filtered_items[sess.current_index]
          if item then
            sess:close()
            vim.cmd("vsplit " .. vim.fn.fnameescape(item.relative_path))
            pcall(vim.api.nvim_win_set_cursor, 0, { item.line_number, 0 })
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
          local item = sess.filtered_items[i]
          if item then
            qf[#qf + 1] = {
              filename = item.relative_path,
              lnum = item.line_number,
              col = item.col or 1,
              text = item.line_content,
            }
          end
        end
        if #qf > 0 then
          sess:close()
          vim.fn.setqflist({}, " ", { title = "Grep Results", items = qf })
          vim.cmd("copen")
        end
      end, { buffer = buf, noremap = true, silent = true })
    end,
  })
end

return M
