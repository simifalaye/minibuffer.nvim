local function win_has_filetype(winid, filetypes)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local filetype = vim.bo[bufnr].filetype
  return vim.tbl_contains(filetypes, filetype)
end

local function is_mb_window(winid)
  return vim.w[winid].minibuffer == true
end

---@param opts table?
return function(opts)
  opts = opts or {}
  if opts.options and opts.options.ignore_focus then
    local ignore_focus = opts.options.ignore_focus
    if type(ignore_focus) == "table" then
      vim.validate({
        ignore_focus = { ignore_focus, vim.islist },
      })
      opts.options.ignore_focus = function(winid)
        return win_has_filetype(winid, ignore_focus) or vim.w[winid].minibuffer == true
      end
    elseif type(ignore_focus) == "function" then
      opts.options.ignore_focus = function(winid)
        return ignore_focus(winid) or is_mb_window(winid)
      end
    else
      opts.options.ignore_focus = function(winid)
        return is_mb_window(winid)
      end
    end
  else
    opts.options = opts.options or {}
    opts.options.ignore_focus = function(winid)
      return is_mb_window(winid)
    end
  end
  require("lualine").setup(opts)
end
