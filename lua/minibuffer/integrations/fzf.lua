local override_opts = {
  fzf_opts = {
    ["--no-separator"] = true,
  },
  winopts = function()
    return {
      height = 0.35,
      width = 1,
      row = 0.35,
      col = 0.50,
      border = "none",
      backdrop = 100,
      relative = "minibuffer",
      use_minibuffer = true,
      winhl = true,
      preview = {
        hidden = "hidden",
      },
    }
  end,
  hls = {
    normal = "Normal",
  },
}

---@param opts table?
return function(opts)
  require("fzf-lua").setup(vim.tbl_deep_extend("force", opts or {}, override_opts))
end
