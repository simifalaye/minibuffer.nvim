local win_config = function()
  local ret = {
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    width = vim.o.columns,
    relative = "minibuffer",
    use_minibuffer = true,
  }
  return ret
end

local override_opts = {
  window = {
    config = win_config,
  },
}

---@param opts table?
return function(opts)
  local default_ui_select = vim.ui.select

  require("mini.pick").setup(vim.tbl_deep_extend("force", opts or {}, override_opts))

  -- NOTE: mini-pick's setup forces itself as the default `ui_select` function.
  vim.ui.select = default_ui_select

  -- Configure highlights
  pcall(vim.api.nvim_set_hl, 0, "MiniPickBorder", { link = "Normal" })
  pcall(vim.api.nvim_set_hl, 0, "MiniPickBorderBusy", { link = "Normal" })
  pcall(vim.api.nvim_set_hl, 0, "MiniPickNormal", { link = "Normal" })
  pcall(vim.api.nvim_set_hl, 0, "MiniPickHeader", { link = "Normal" })
end
