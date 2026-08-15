--
-- Base types
--

---@alias minibuffer.core.SessionType 'cmd'|'display'|'input'|'scratch'|'select'

---@class minibuffer.core.Session
---@field resumable boolean
---@field closed boolean
---@field type fun(self: minibuffer.core.Session): minibuffer.core.SessionType
---@field overridable fun(self: minibuffer.core.Session): boolean
---@field pre_start fun(self: minibuffer.core.Session)
---@field render fun(self: minibuffer.core.Session)
---@field post_start fun(self: minibuffer.core.Session)
---@field cancel fun(self: minibuffer.core.Session)
---@field close fun(self: minibuffer.core.Session)
local Session = {}
Session.__index = Session

---@class minibuffer.core.HighlightChunk
---@field text string
---@field hl string|nil

---@alias minibuffer.core.HighlightLine minibuffer.core.HighlightChunk[]

---@alias minibuffer.core.ItemCompareFn fun(old:any, new:any): boolean
---@alias minibuffer.core.FormatFn fun(item:any): minibuffer.core.HighlightLine
---@alias minibuffer.core.CancelCallback fun()
---@alias minibuffer.core.CloseCallback fun(done?:fun())
---@alias minibuffer.core.ChangeCallback fun(value:string, item:any)

---@alias minibuffer.util.Keyset fun(modes:string|string[], lhs:string, rhs:string|function, opts?:vim.keymap.set.Opts)
