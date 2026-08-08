---@class minibuffer.examples.DiagnosticsOpts
---@field scope? "buffer"|"workspace"

---@type minibuffer.examples.DiagnosticsOpts
local opts = {
  scope = "workspace",
}

local severity_names = {
  [vim.diagnostic.severity.ERROR] = "Error",
  [vim.diagnostic.severity.WARN] = "Warn",
  [vim.diagnostic.severity.INFO] = "Info",
  [vim.diagnostic.severity.HINT] = "Hint",
}

local severity_hls = {
  [vim.diagnostic.severity.ERROR] = "DiagnosticError",
  [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
  [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
  [vim.diagnostic.severity.HINT] = "DiagnosticHint",
}

local function gather_diagnostics(scope)
  local diagnostics = scope == "buffer" and vim.diagnostic.get(0) or vim.diagnostic.get()

  local items = {}
  for _, diag in ipairs(diagnostics) do
    local file = vim.api.nvim_buf_get_name(diag.bufnr)
    items[#items + 1] = {
      bufnr = diag.bufnr,
      file = file,
      lnum = diag.lnum,
      col = diag.col,
      severity = diag.severity,
      source = diag.source or "",
      message = diag.message:gsub("\n", " "),
    }
  end

  return items
end

local function format_fn(item)
  return {
    {
      text = severity_names[item.severity],
      hl = severity_hls[item.severity],
    },
    {
      text = "  " .. vim.fn.fnamemodify(item.file, ":."),
      hl = "Comment",
    },
    {
      text = ":" .. (item.lnum + 1),
      hl = "Number",
    },
    {
      text = "  " .. item.message,
      hl = "Normal",
    },
  }
end

local function filter_fn(items, input)
  if input == "" then
    return items
  end

  local lookup = {}
  local keys = {}
  for _, item in ipairs(items) do
    local key = table.concat({
      item.message,
      item.file,
      item.source,
      severity_names[item.severity],
    }, " ")
    keys[#keys + 1] = key
    lookup[key] = item
  end

  local matches = vim.fn.matchfuzzy(keys, input)
  local results = {}
  for _, key in ipairs(matches) do
    results[#results + 1] = lookup[key]
  end
  return results
end

---@param o? minibuffer.examples.DiagnosticsOpts
return function(o)
  opts = vim.tbl_deep_extend("force", opts, o or {})

  require("minibuffer").select({
    resumable = true,
    prompt = opts.scope == "buffer" and "Buffer Diagnostics: "
      or "Workspace Diagnostics: ",
    items = gather_diagnostics(opts.scope),
    multi = false,
    allow_shrink = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    on_select = function(selection)
      local item = selection[1]
      if not item then
        return
      end
      vim.api.nvim_set_current_buf(item.bufnr)
      vim.api.nvim_win_set_cursor(0, {
        item.lnum + 1,
        item.col,
      })
      vim.cmd("normal! zvzz")
    end,
  })
end
