local override_opts = {
  win = {
    relative = "minibuffer",
    use_minibuffer = true,
  },
}

---@param opts table?
return function(opts)
  require("which-key").setup(vim.tbl_deep_extend("force", opts or {}, override_opts))

  -- Set highlights to match command window
  pcall(vim.api.nvim_set_hl, 0, "WhichKeyNormal", { link = "Normal" })
end
