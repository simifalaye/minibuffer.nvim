--
-- Base types
--

---@alias minibuffer.core.SessionType 'display'|'input'|'scratch'|'select'

---@class minibuffer.core.Session
--- Get the type of a session
---@field type fun(self: minibuffer.core.Session): minibuffer.core.SessionType
--- Check if a session is overridable
---@field overridable fun(self: minibuffer.core.Session): boolean
--- Check if a session is resumable
---@field resumable fun(self: minibuffer.core.Session): boolean
--- Session setup
---@field pre_start fun(self: minibuffer.core.Session)
--- Render session to the screen
---@field render fun(self: minibuffer.core.Session)
--- After first render
---@field post_start fun(self: minibuffer.core.Session)
--- Cancel session
---@field cancel fun(self: minibuffer.core.Session)
--- Close session
---@field close fun(self: minibuffer.core.Session, done: fun()|nil)
local Session = {}
Session.__index = Session

---@alias minibuffer.core.ItemCompareFn fun(old:any, new:any): boolean
---@alias minibuffer.core.FormatFn fun(item:any): minibuffer.util.HighlightLine
---@alias minibuffer.core.CancelCallback fun()
---@alias minibuffer.core.CloseCallback fun(done?:fun())
---@alias minibuffer.core.ChangeCallback fun(value:string, item:any)

---@class minibuffer.util.HighlightChunk
---Text to display
---@field text string
---Highlight for the text
---@field hl string|nil

---@alias minibuffer.util.HighlightLine minibuffer.util.HighlightChunk[]

---@class minibuffer.util.WriteLinesOpts
---Starting line in the buffer to write to (0-based)
---@field start_line integer|nil
---Whether to replace text in the buffer
---@field replace_existing boolean|nil

---@alias minibuffer.util.Keyset fun(modes:string|string[], lhs:string, rhs:string|function, opts?:vim.keymap.set.Opts)

---@class minibuffer.util.WindowState
---The height of the window
---@field height integer
---The buffer attached to the window
---@field buf integer
---The saved winview
---@field view vim.fn.winsaveview.ret

local M = {}
return M
