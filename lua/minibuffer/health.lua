local M = {}

local function check_neovim_version()
  local version = vim.version()

  if vim.fn.has("nvim-0.12") then
    vim.health.ok(("Neovim %d.%d.%d"):format(version.major, version.minor, version.patch))
    return true
  end

  vim.health.error(
    "Neovim 0.12.0 or later is required",
    nil,
    ("Found Neovim %d.%d.%d"):format(version.major, version.minor, version.patch)
  )

  return false
end

local function check_ui2()
  local ok, ui2 = pcall(require, "vim._core.ui2")
  if ok and ui2 and ui2.cfg.enable and ui2.wins.cmd > 0 and ui2.bufs.cmd > 0 then
    vim.health.ok("Neovim UI2 is enabled")
    return true
  end
  vim.health.error(
    "Neovim UI2 is not available/enabled",
    nil,
    "Call require('vim._core.ui2').enable({ enable = true, msg = { targets = 'msg' } }) before loading minibuffer"
  )
  return false
end

function M.check()
  vim.health.start("minibuffer")

  -- Prerequisites.
  if not check_neovim_version() then
    return
  end
  if not check_ui2() then
    return
  end

  -- Configuration.
  local ok, config = pcall(require, "minibuffer.config")
  if not ok then
    vim.health.error("configuration is invalid", nil, config)
    return
  end

  local user_config = vim.g.minibuffer
  if type(user_config) == "function" then
    local success, result = pcall(user_config)
    if not success then
      vim.health.error("vim.g.minibuffer function failed", nil, result)
      return
    end
    user_config = result
  end
  user_config = user_config or {}

  local validate = require("minibuffer.config.validate")
  local valid, err = validate.validate(user_config)
  if not valid then
    vim.health.error("configuration is invalid", nil, err)
    return
  end

  vim.health.ok("configuration is valid")
end

return M
