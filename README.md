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

The goal of this plugin is to eventually put some simple version of this into neovim core if desired by the maintainers. See [this issue](https://github.com/neovim/neovim/issues/35456)

I have integration implementations in `lua/minibuffer/integrations` with existing plugins.

# Prerequisites

- `neovim >= 0.12`
- ui2 enable somewhere early in your init.lua:

```lua
require("vim._core.ui2").enable({ enable = true, msg = { targets = "msg" } })
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
  dynamic_window_resize = true, -- Shrink other windows when the minibuffer is expanded
  cmd = {
    -- NOTE: minibuffer cmd is not compatible with command line plugins that force `wildtrigger()` each `wildchar` such as mini.cmdline
    enabled = true, -- Enable command line wildmenu replacement through the minibuffer
    autotrigger = true, -- Display completion suggestions as you type
    dynamic_height = false, -- Whether the completion window should shrink as items disappear.
    max_height = 15, -- Maximum height when using the command line
   },
}
```

# Examples

I have written a few usable examples for this interface for demonstration.

## Custom Pickers

```lua
vim.keymap.set("n", "<leader>;", function()
  require("minibuffer.examples.history")({ type = "cmd" })
end, { desc = "Find command history" })
vim.keymap.set("n", "<leader>?", function()
  require("minibuffer.examples.history")({ type = "search" })
end, { desc = "Find command history" })
vim.keymap.set("n", "<leader>'", function()
  require("minibuffer.examples.marks")()
end, { desc = "Find mark" })
vim.keymap.set(
  "n",
  "<leader>/",
  require("minibuffer.examples.live-grep"),
  { desc = "Live grep" }
)

vim.keymap.set(
  "n",
  "<leader>fb",
  require("minibuffer.examples.buffers"),
  { desc = "Find buffers" }
)
vim.keymap.set(
  "n",
  "<leader>ff",
  require("minibuffer.examples.files"),
  { desc = "Find files" }
)
vim.keymap.set("n", "<leader>fd", function()
  require("minibuffer.examples.diagnostics")({ scope = "buffer" })
end, { desc = "Find diagnostics" })
vim.keymap.set("n", "<leader>fD", function()
  require("minibuffer.examples.diagnostics")({ scope = "workspace" })
end, { desc = "Find diagnostics (workspace)" })
vim.keymap.set(
  "n",
  "<leader>fg",
  require("minibuffer.examples.git-files"),
  { desc = "Find gitfiles" }
)
vim.keymap.set("n", "<leader>fl", function()
  require("minibuffer.examples.list")({ type = "loclist" })
end, { desc = "Find in loclist" })
vim.keymap.set(
  "n",
  "<leader>fm",
  require("minibuffer.examples.manpages"),
  { desc = "Find manpages" }
)
vim.keymap.set("n", "<leader>fo", function()
  require("minibuffer.examples.oldfiles")({ cwd = vim.fn.getcwd() })
end, { desc = "Find oldfiles (cwd)" })
vim.keymap.set(
  "n",
  "<leader>fO",
  require("minibuffer.examples.oldfiles"),
  { desc = "Find oldfiles (all)" }
)
vim.keymap.set("n", "<leader>fq", function()
  require("minibuffer.examples.list")({ type = "quickfix" })
end, { desc = "Find in quickfix" })
```

## Interesting things you can do when using the minibuffer command line

**Doom-emacs M-x file explorer picker**

```lua
vim.keymap.set("n", "<leader>.", function()
  local buf_path = vim.api.nvim_buf_get_name(0)
  local dir = vim.fn.fnamemodify(buf_path, ":p:h")
  if dir == "" then
    dir = "."
  end
  local cmd = ":e " .. vim.fn.fnameescape(dir) .. "/"
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "n", true)
end, { desc = "Find file" })
```

**Pick help-tags**

```lua
vim.keymap.set("n", "<leader>hh", ":h ", { desc = "Help" })
```

# Integrations with existing plugins

Two integration types can be seen below:
- Using the backend of a plugin with the minibuffer frontend APIs (as seen in the fff.nvim example below)
- Allowing each plugin to draw their own window but configuring the window settings to put it into the minibuffer container (as seen in the which-key.nvim, mini.pick and fzf.lua examples below)

When possible, the first option is preferred.
Some plugins don't expose their data fetching code through their public APIs an in such cases the second option can be used.
This is done by using some specific markers in the window configuration to allow us to know which windows should be drawn in the minibuffer container.
There are two markers supported in the window configuration:
- Setting the `use_minibuffer = true`
- Setting `relative = "minibuffer"`

I recommend using both at the same time to ensure that none of the markers are overridden by the plugin's configuration setup.

## Which-key.nvim

<img width="2560" height="1440" alt="which-key nvim-integration" src="https://github.com/user-attachments/assets/993b040f-dcd9-4fb3-b861-1ad1f8fc2824" />

```lua
-- Setup plugin with minibuffer window config
require("which-key").setup({
  win = { 
    relative = "minibuffer",
    use_minibuffer = true,
  },
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
    relative = "minibuffer",
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

## fzf.lua

```lua
require("fzf-lua").setup({
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
    }
  end,
  hls = {
    normal = "Normal",
  },
  -- Depending on your fzf-lua version/config structure,
  -- this is best applied to the individual pickers:
  files = {
    previewer = false,
  },
  buffers = {
    previewer = false,
  },
  grep = {
    previewer = false,
  },
  live_grep = {
    previewer = false,
  },
})
```

# Statusline Integration

You may notice that when the minibuffer is open in an interactive session (such as select or input), the 'inactive' statusline is shown.
This is because you are focussed on another command window (which doesn't draw another statusline) and so you need to tell your statusline code which window to draw the active statusline for.
Minibuffer keeps track of the last window that was in use before it opened `get_active_window()`.
You can use this function to determine whether to draw the active/inactive statusline for a window.
I have this code setup in my statusline config to determine whether to draw the inactive statusline (return `true` means draw the inactive statusline for this window):
```lua
local winid = vim.api.nvim_get_current_win()
local curwin = tonumber(vim.g.actual_curwin)
-- If this is the active window then don't display inactive statusline
if winid == curwin then
  return false
end
-- If the current window is a floating, then look at the previously accessed window
if vim.api.nvim_win_get_config(winid).relative ~= "" then
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev == curwin then
    return false
  end
end
-- If the minibuffer is active, determine whether this was the last active window
local mb_ok, mb = pcall(require, "minibuffer")
if mb_ok and mb.get_active_window() == winid then
  return false
end
return true
```

# Developer Notes

API documentation for the various minibuffer session types and overall plugin will come as the API stabilizes a bit more.
As such, please refer to the following files/directories that contain the type definitions/options:
* `lua/minibuffer/types.lua`
- `lua/minibuffer/sessions/*`

For examples on how the options can be used, see `lua/minibuffer/examples/*`
