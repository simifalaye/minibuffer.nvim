# Minibuffer

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

A **highly experimental** general purpose interactive interface for neovim.

https://github.com/user-attachments/assets/5d6dea18-9f13-460e-954c-413ff4f4d302

**NOTE**:

- This plugin is still under development and will see some breaking changes (feel free to pin to a commit)
- It depends on an experimental feature in neovim (`vim._core.ui2`)

This plugin provides an API for an optional unified interactive buffer interface.
Instead of having one plugin open a floating pop-up for fuzzy file search, another showing a completion menu at the bottom, another drawing commandline completions above the status bar and yet another drawing a general purpose picker in a different location, you can choose to have one place where interactive input can be shown that feels native to the editor and is predictable.
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

I have integration implementations in `lua/minibuffer/integrations` with existing plugins.

# Prerequisites

- `neovim >= 0.12`
- ui2 enable somewhere early in your init.lua:

```lua
require("vim._core.ui2").enable({ enable = true, msg = { target = "msg" } })
```

# Installation

**NOTE:** You will want to load minibuffer.nvim as one of your earliest plugins (DO NOT LAZY LOAD).

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

vim.keymap.set("n", "<leader><CR>", function()
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

  vim.keymap.set("n", "<leader><CR>", function()
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

    vim.keymap.set("n", "<leader><CR>", function()
      minibuffer.resume(true)
    end)
  end,
}
```

# Configuration

This plugin can be configured by using `vim.g.minibuffer` (preferably set before the plugin loads).
```lua
-- Default configuration
vim.g.minibuffer = {
  cmd = {
    enabled = true, -- Enable command line wildmenu replacement through the minibuffer
    dynamic_height = false, -- Automatically shrink and grow the command window as suggestions change
    max_height = 15, -- Maximum height when using the command line
   },
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

<img width="2560" height="1440" alt="which-key nvim-integration" src="https://github.com/user-attachments/assets/993b040f-dcd9-4fb3-b861-1ad1f8fc2824" />

```lua
-- Setup plugin with minibuffer window config
require("which-key").setup({
  win = { use_minibuffer = true },
})

-- Set highlights to match command window
pcall(vim.api.nvim_set_hl, 0, "WhichKeyNormal", { link = "Normal" })
```

## FFF.nvim

<img width="2560" height="1440" alt="fff nvim-integration" src="https://github.com/user-attachments/assets/2595ab60-e77c-4695-b26d-61b01b09d456" />

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

<img width="2560" height="1440" alt="mini pick-integration" src="https://github.com/user-attachments/assets/0fe78407-f95f-4223-85e7-bad07484a781" />

```lua
local win_config = function()
  local ret = {
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    width = vim.o.columns,
    use_minibuffer = true,
  }
  return ret
end

local default_ui_select = vim.ui.select

-- Setup plugin with minibuffer window configuration
pick.setup({
  window = { config = win_config },
})

-- NOTE: mini-pick's setup forces itself as the default `ui_select` function.
-- You will need to save the old one before and restore it after `setup()` if you wish to use the default minibuffer `ui_select`.
vim.ui.select = default_ui_select

-- Set highlights to match command window
pcall(vim.api.nvim_set_hl, 0, "MiniPickBorder", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickBorderBusy", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickNormal", { link = "Normal" })
pcall(vim.api.nvim_set_hl, 0, "MiniPickHeader", { link = "Normal" })

-- Use mini.pick's internal resume function to resume the picker
vim.keymap.set("n", "<leader><CR>", "<cmd>Pick resume<CR>", { desc = "Resume Picker" })
```
