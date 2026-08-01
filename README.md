# Minibuffer

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

A **highly experimental** general purpose interactive interface for neovim.

https://github.com/user-attachments/assets/d69b3d3a-03d9-4285-aebb-23d1d895b831

**NOTE**:

- This plugin is still under development
- It depends on an experimental feature in neovim (`vim._core.ui2`)

This plugin provides an api for an optional unified interactive buffer interface.
Instead of having one plugin open a floating popup for fuzzy file search, another showing a completion menu at the bottom, another drawing commandline completions above the status bar and yet another drawing a general purpose picker in a different location, you can choose to have one place where interactive input can be shown that feels native to the editor and is predictable.
This includes:

- Running commands with completion.
- Fuzzy finding files or buffers.
- Searching text across a project.
- Input prompts for LSP or Git actions.
- Even interactive plugin UIs (think Telescope, fzf, etc).
- Display timely content (think which-key.nvim or mini.pick)

For Neovim, something like this could replace the ad-hoc popup/floating windows many plugins use, giving us a consistent workflow: a single expandable buffer for all kinds of input and interactive tasks.

# Goal

The goal of this plugin is to eventually put some form of `lua/minibuffer/core.lua` into neovim core if desired by the maintainers.

Since this interface exists as plugin for now, it will require an integration layer with other plugins to use their backend.
I have integration implementations in `lua/minibuffer/integrations`.

# Prerequisites

- `neovim >= 0.12`
- ui2 enable somewhere early in your init.lua:

```lua
require("vim._core.ui2").enable({ enable = true, msg = { target = "msg" } })
```

# Installation

**MAKE SURE YOU HAVE ENABLED vim.\_core.ui2 (See prerequisites)**

- vim.pack

```lua
vim.pack.add({
  {
    src = "https://github.com/simifalaye/minibuffer.nvim",
  },
})

local minibuffer = require("minibuffer")

vim.ui.select = require("minibuffer.builtin.ui_select")
vim.ui.input = require("minibuffer.builtin.ui_input")

vim.keymap.set("n", "<M-;>", ":")
vim.keymap.set("n", ":", require("minibuffer.builtin.cmdline"))
vim.keymap.set("n", "<M-.>", function()
  minibuffer.resume(true)
end)
```

- [mini.deps](https://github.com/nvim-mini/mini.deps)

```lua
MiniDeps.now(function()
  MiniDeps.add({
    source = "simifalaye/minibuffer.nvim",
  })

  local minibuffer = require("minibuffer")

  vim.ui.select = require("minibuffer.builtin.ui_select")
  vim.ui.input = require("minibuffer.builtin.ui_input")

  vim.keymap.set("n", "<M-;>", ":")
  vim.keymap.set("n", ":", require("minibuffer.builtin.cmdline"))
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

    vim.keymap.set("n", "<M-;>", ":")
    vim.keymap.set("n", ":", require("minibuffer.builtin.cmdline"))
    vim.keymap.set("n", "<M-.>", function()
      minibuffer.resume(true)
    end)
  end,
}
```

# Examples

I have written a few usable examples for this interface for demonstration.

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

# Integrations with existing plugins

## Which-key.nvim

<img width="2534" height="1333" alt="which-key-integration" src="https://github.com/user-attachments/assets/636e0026-4e17-4bc8-9535-396fccb256fc" />

```lua
-- Setup plugin with minibuffer window config
require("which-key").setup({
  win = { use_minibuffer = true },
})

-- Set highlights to match command window
pcall(vim.api.nvim_set_hl, 0, "WhichKeyNormal", { link = "Normal" })
```

## FFF.nvim

<img width="2542" height="1342" alt="fff-integration" src="https://github.com/user-attachments/assets/2fdacf4f-35ba-479f-adb8-cf8e39b7d512" />

```lua
-- NOTE: after loading plugin
local fff_mb = require("minibuffer.integrations.fff")

vim.keymap.set("n", "<leader><leader>", function()
  fff_mb.file_search({})
end, { desc = "FFFind" })

vim.keymap.set("n", "<leader>/", function()
  fff_mb.content_search({})
end, { desc = "FFFGrep" })
```

## mini-pick.nvim

<img width="2538" height="1333" alt="mini-pick-integration" src="https://github.com/user-attachments/assets/eec8c0f3-fc71-46ae-ba3e-bdbaceb4188c" />

```lua
local win_config = function()
  local ret = {
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    width = vim.o.columns,
    use_minibuffer = true,
  }
  return ret
end

-- Setup plugin with minibuffer window config
pick.setup({
  window = { config = win_config },
})

-- Set highlights to match command window
pcall(vim.api.nvim_set_hl, 0, "MiniPickBorder", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickBorderBusy", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickNormal", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickHeader", { link = "Normal" })

-- Use mini.pick's internal resume function to resume the picker
vim.keymap.set("n", "<leader><CR>", "<cmd>Pick resume<CR>", { desc = "Resume Picker" })
```
