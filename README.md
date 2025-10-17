# Minibuffer

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

A **highly experimental** general purpose interactive interface for neovim.

**NOTE**:
- This plugin is still under development
- It depends on an experimental feature in neovim nightly (`vim._extui`)

This plugin provides an api for an optional unified interactive buffer
interface. Instead of having one plugin open a floating popup for fuzzy
file search, another showing a completion menu at the bottom, another
drawing commandline completions above the status bar and yet another
drawing a general purpose picker in a different location, we can have
one place where interactive input can be shown that feels native to the
editor and is predictable. This includes:
- Running commands with completion.
- Fuzzy finding files or buffers.
- Searching text across a project.
- Input prompts for LSP or Git actions.
- Even interactive plugin UIs (think Telescope, fzf, etc).

For Neovim, something like this could replace the ad-hoc popup/floating
windows many plugins use, giving us a consistent workflow: a single
expandable buffer for all kinds of input and interactive tasks.

# Goal

The goal of this plugin is to eventually put some form of
`lua/minibuffer/core.lua` into neovim core if desired by the
maintainers.

Since this interface exists as plugin for now, it will require an
integration layer with other plugins to use their backend. I have
provided an example for the [which-key.nvim](https://github.com/folke/which-key.nvim) plugin
found at `lua/minibuffer/examples/which-key.lua`.

# Prerequisites

- `neovim >= 0.12` (currently on nightly)
- Extui enable somewhere early in your init.lua:
```lua
require("vim._extui").enable({ enable = true, msg = { target = "msg" } })
```

# Installation

**MAKE SURE YOU HAVE ENABLED vim._extui (See prerequisites)**

- [mini.deps](https://github.com/nvim-mini/mini.deps)

```lua
MiniDeps.now(function()
  MiniDeps.add({
    source = "simifalaye/minibuffer.nvim",
  })

  local minibuffer = require("minibuffer")

  vim.ui.select = require("minibuffer.builtin.ui_select")
  vim.ui.input = require("minibuffer.builtin.ui_input")

  vim.keymap.set("n", "<M-;>", require("minibuffer.builtin.cmdline"))
  vim.keymap.set("n", "<M-.>", function()
    minibuffer.resume(true)
  end)
end)
```

- [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "simifalaye/minibuffer.nvim",
  init = function()
    local minibuffer = require("minibuffer")

    vim.ui.select = require("minibuffer.builtin.ui_select")
    vim.ui.input = require("minibuffer.builtin.ui_input")

    vim.keymap.set("n", "<M-;>", require("minibuffer.builtin.cmdline"))
    vim.keymap.set("n", "<M-.>", function()
      minibuffer.resume(true)
    end)
  end,
}
```

# Examples

I have written a few usable examples for this interface for
demonstration.

## Which-key integration

```lua
local wk = require("which-key")
wk.setup({})
require("minibuffer.examples.which-key")()
```

## Custom Pickers

```lua
vim.keymap.set("n", "<leader>.", require("minibuffer.examples.files"))
vim.keymap.set("n", "<leader>,", require("minibuffer.examples.buffers"))
vim.keymap.set("n", "<leader>/", require("minibuffer.examples.live-grep"))
vim.keymap.set("n", "<leader>o", function()
  require("minibuffer.examples.oldfiles")({ cwd = vim.fn.getcwd() })
end)
vim.keymap.set("n", "<leader>O", require("minibuffer.examples.oldfiles"))
```
