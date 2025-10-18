local M = {}

local display = nil

---@param items wk.Item[]
---@return minibuffer.core.HighlightLine[]
local function items_to_highlight_lines(items)
  local wk_view = require("which-key.view")
  local State = require("which-key.state")
  local state = State.state
  if not state then
    return {}
  end

  local wk_config = require("which-key.config")
  local spacing = wk_config.layout.spacing or 3
  local min_w = (wk_config.layout.width and wk_config.layout.width.min) or 20
  local max_w = (wk_config.layout.width and wk_config.layout.width.max) or min_w
  local padding = wk_config.win and wk_config.win.padding or { 0, 0 }
  local pad_tb, pad_lr = padding[1] or 0, padding[2] or 0

  -- normalize items
  local normalized = {}
  for _, it in ipairs(items) do
    local key = it.key or ""
    local sep = " : "
    local icon = it.icon or ""
    local icon_pad = icon ~= "" and " " or ""
    local desc = (it.desc and it.desc ~= "") and it.desc or "<unknown>"

    local fixed_len = #key + #sep + #icon + #icon_pad

    normalized[#normalized + 1] = {
      key = key,
      sep = sep,
      icon = icon,
      icon_pad = icon_pad,
      fixed_len = fixed_len,
      desc = desc,
      key_hl = "Normal",
      sep_hl = "WhichKeySeparator",
      icon_hl = it.icon_hl,
      desc_hl = (it.group and "WhichKeyGroup") or "WhichKeyDesc",
    }
  end

  -- decide effective cell width
  local cell_width = math.max(min_w, math.min(max_w, min_w))

  -- determine how many columns fit
  local win_width = vim.o.columns
  local col_stride = cell_width + spacing
  local num_cols = math.max(1, math.floor((win_width + spacing) / col_stride))

  -- column-major layout
  local n = #normalized
  local box_height = math.max(math.ceil(n / num_cols), 1)

  -- build one fixed-width cell with truncated desc
  local function build_cell(nitem)
    local avail_desc = math.max(0, cell_width - nitem.fixed_len)
    local truncated = nitem.desc or ""
    if #truncated > avail_desc then
      if avail_desc >= 1 then
        truncated = truncated:sub(1, avail_desc - 1) .. "…"
      else
        truncated = ""
      end
    end

    local chunks = {}
    chunks[#chunks + 1] = { text = nitem.key, hl = nitem.key_hl }
    chunks[#chunks + 1] = { text = nitem.sep, hl = nitem.sep_hl }
    if nitem.icon ~= "" then
      chunks[#chunks + 1] = { text = nitem.icon, hl = nitem.icon_hl }
      chunks[#chunks + 1] = { text = nitem.icon_pad }
    end
    if truncated ~= "" then
      chunks[#chunks + 1] = { text = truncated, hl = nitem.desc_hl }
    end

    -- pad to exact cell width
    local len = 0
    for _, c in ipairs(chunks) do
      len = len + #c.text
    end
    local pad = cell_width - len
    if pad > 0 then
      chunks[#chunks + 1] = { text = string.rep(" ", pad) }
    end
    return chunks
  end

  -- build lines: l = 1..box_height, b = 1..num_cols, idx = (b-1)*box_height + l
  local lines = {}
  for l = 1, box_height do
    local row_chunks = {}
    -- left padding
    if pad_lr > 0 then
      row_chunks[#row_chunks + 1] = { text = string.rep(" ", pad_lr) }
    end

    for b = 1, num_cols do
      local idx = (b - 1) * box_height + l
      local item = normalized[idx]

      if b ~= 1 then
        row_chunks[#row_chunks + 1] = { text = string.rep(" ", spacing) }
      end

      if item then
        local cell_chunks = build_cell(item)
        for _, ch in ipairs(cell_chunks) do
          row_chunks[#row_chunks + 1] = ch
        end
      else
        row_chunks[#row_chunks + 1] = { text = string.rep(" ", cell_width) }
      end
    end

    -- right padding
    if pad_lr > 0 then
      row_chunks[#row_chunks + 1] = { text = string.rep(" ", pad_lr) }
    end

    lines[#lines + 1] = row_chunks
  end

  -- add top/bottom padding as empty lines
  if pad_tb > 0 then
    local empty_line = {
      {
        text = string.rep(
          " ",
          #lines[1]
              and vim.fn.strdisplaywidth(table.concat(vim.tbl_map(function(c)
                return c.text
              end, lines[1])))
            or 0
        ),
      },
    }
    for _ = 1, pad_tb do
      table.insert(lines, 1, empty_line)
      table.insert(lines, empty_line)
    end
  end

  local footer_chunks = {}

  if wk_config.show_keys then
    footer_chunks[#footer_chunks + 1] = { text = " " }
    for _, segment in ipairs(wk_view.trail(state.node) or {}) do
      footer_chunks[#footer_chunks + 1] = { text = segment[1], hl = segment[2] }
    end
  end

  if wk_config.show_help then
    local keys = {
      { key = "<esc>", desc = "close" },
    }
    if state.node.parent then
      keys[#keys + 1] = { key = "<bs>", desc = "back" }
    end

    for k, key in ipairs(keys) do
      footer_chunks[#footer_chunks + 1] = { text = key.key, hl = "WhichKey" }
      footer_chunks[#footer_chunks + 1] =
        { text = " " .. key.desc, hl = "WhichKeySeparator" }
      if k < #keys then
        footer_chunks[#footer_chunks + 1] = { text = "  " }
      end
    end
  end

  if #footer_chunks > 0 then
    local footer_text = table.concat(vim.tbl_map(function(c)
      return c.text
    end, footer_chunks))
    local footer_width = vim.fn.strdisplaywidth(footer_text)
    local pad_left = math.max(0, math.floor((win_width - footer_width) / 2))
    table.insert(lines, { { text = string.rep(" ", pad_left) } })
    for _, ch in ipairs(footer_chunks) do
      table.insert(lines[#lines], ch)
    end
  end

  return lines
end

function M.show()
  local wk_view = require("which-key.view")
  local State = require("which-key.state")
  local state = State.state
  if not (state and state.show and state.node:is_group()) then
    wk_view.hide()
    return
  end

  ---@type wk.Node[]
  local children = state.node:children()

  if state.filter.global == false and state.filter.expand == nil then
    state.filter.expand = true
  end

  ---@param node wk.Node
  local function filter(node)
    local l = state.filter["local"] ~= false
    local g = state.filter.global ~= false
    if not g and not l then
      return false
    end
    if g and l then
      return true
    end
    local is_local = node:is_local()
    return l and is_local or g and not is_local
  end

  ---@param node wk.Node
  local function expand(node)
    if node:is_plugin() then
      return false
    end
    if state.filter.expand then
      return true
    end
    if node:can_expand() then
      return false
    end
    local child_count = node:count()
    return child_count > 0 and child_count <= 0
  end

  ---@type wk.Item[]
  local items = {}
  for _, node in ipairs(children) do
    vim.list_extend(items, wk_view.expand(state.node, node, expand, filter))
  end

  wk_view.sort(items)

  local lines = items_to_highlight_lines(items)
  local minibuffer = require("minibuffer")
  if display then
    if not display:update_lines(lines) then
      display = nil
    end
  else
    minibuffer.display({
      lines = lines,
      timeout = 0,
      allow_shrink = true,
    })
    display = minibuffer.get_active_session()
  end
end

function M.hide()
  if display then
    display:close()
    display = nil
  end
end

return M
