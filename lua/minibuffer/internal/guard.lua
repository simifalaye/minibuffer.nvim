local state = require("minibuffer.internal.state")

local M = {}

function M.check()
  if state.initialized then
    return
  end
  error(
    "Minibuffer MUST be initialized first; call require('minibuffer').initialize()",
    2
  )
end

return M
