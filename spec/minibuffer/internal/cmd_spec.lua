local config = require("minibuffer.config")
local helper = require("helper")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")
local assert, match, spy = helper.init()

describe("minibuffer.internal.cmd", function()
  local cmd
  local buf
  local win
  local ui_callback

  local vim_api
  local vim_fn
  local vim_keymap

  local vim_ui_attach
  local vim_ui_detach

  before_each(function()
    helper.init_stubs()

    package.loaded["minibuffer.internal.cmd"] = nil
    cmd = require("minibuffer.internal.cmd")
    buf = 1
    win = 2
    ui_callback = nil

    vim_api = vim.api
    vim_fn = vim.fn
    vim_keymap = vim.keymap

    state.ns = 42
    state.win_states = nil

    helper.stub_method(util, "get_cmd_win", function()
      return 3
    end)
    helper.stub_method(util, "get_window_states", function()
      return { [1] = { height = 22, buf = 1, view = {} } }
    end)
    helper.stub_method(util, "set_win_height")
    helper.stub_method(util, "set_cmdheight")
    helper.stub_method(util, "write_highlighted_lines")
    helper.stub_method(util, "restore_window_states")

    helper.stub_method(state, "cleanup")

    helper.stub_method(vim_api, "nvim_buf_is_valid", function()
      return true
    end)
    helper.stub_method(vim_api, "nvim_win_is_valid", function()
      return true
    end)
    helper.stub_method(vim_api, "nvim_create_buf", function()
      return buf
    end)
    helper.stub_method(vim_api, "nvim_open_win", function()
      return win
    end)
    helper.stub_method(vim_api, "nvim_win_get_config", function()
      return { zindex = 100 }
    end)
    helper.stub_method(vim_api, "nvim_win_get_height", function()
      return 1
    end)
    helper.stub_method(vim_api, "nvim_win_call", function(_, callback)
      callback()
    end)
    helper.stub_method(vim_api, "nvim_set_option_value")
    helper.stub_method(vim_api, "nvim_buf_set_lines")
    helper.stub_method(vim_api, "nvim_buf_clear_namespace")
    helper.stub_method(vim_api, "nvim_buf_set_extmark", function()
      return 10
    end)
    helper.stub_method(vim_api, "nvim_buf_del_extmark")
    helper.stub_method(vim_api, "nvim__redraw")
    helper.stub_method(vim_api, "nvim_win_close")
    helper.stub_method(vim_api, "nvim_buf_delete")
    helper.stub_method(vim_api, "nvim_get_commands", function()
      return {}
    end)
    helper.stub_method(vim_api, "nvim_set_current_win")

    vim_ui_attach = helper.stub_method(vim, "ui_attach", function(_, _, callback)
      ui_callback = callback
    end)

    vim_ui_detach = helper.stub_method(vim, "ui_detach")

    helper.stub_method(vim, "schedule", function(callback)
      callback()
    end)

    helper.stub_method(vim, "keycode", function(key)
      return key
    end)

    helper.stub_method(vim_fn, "getcmdtype", function()
      return ":"
    end)
    helper.stub_method(vim_fn, "getcmdline", function()
      return ""
    end)
    helper.stub_method(vim_fn, "wildmenumode", function()
      return 0
    end)
    helper.stub_method(vim_fn, "mode", function()
      return "c"
    end)
    helper.stub_method(vim_fn, "wildtrigger")

    helper.stub_method(vim_keymap, "set")
    helper.stub_method(vim_keymap, "del")

    config.cmd.enabled = true
    config.cmd.autotrigger = false
    config.cmd.dynamic_height = false
    config.cmd.max_height = 15
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  describe(".enable", function()
    it("does nothing when command completion is disabled", function()
      config.cmd.enabled = false

      cmd.enable()

      assert.is_false(cmd.is_active())
      assert.stub(vim_api.nvim_create_buf).called_at_most(0)
      assert.stub(vim_ui_attach).called_at_most(0)
    end)

    it("does nothing when already active", function()
      cmd.enable()
      assert.is_true(cmd.is_active())

      vim_api.nvim_create_buf:clear()

      cmd.enable()

      assert.stub(vim_api.nvim_create_buf).called_at_most(0)
    end)

    it("does nothing when the command window is unavailable", function()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      cmd.enable()

      assert.is_false(cmd.is_active())
      assert.stub(vim_api.nvim_create_buf).called_at_most(0)
      assert.stub(vim_ui_attach).called_at_most(0)
    end)

    it("creates the completion buffer and window", function()
      cmd.enable()

      assert.stub(vim_api.nvim_create_buf).called_with(false, true)
      assert.stub(vim_api.nvim_open_win).called_with(buf, false, match.is_table())
    end)

    it("configures the completion window", function()
      cmd.enable()

      local options = {}

      for _, call in ipairs(vim_api.nvim_set_option_value.calls) do
        options[call.refs[1]] = call.refs[2]
      end

      assert.equal("", options.filetype)
      assert.equal("all", options.eventignorewin)
      assert.is_false(options.wrap)
      assert.is_false(options.linebreak)
      assert.is_false(options.swapfile)
      assert.is_true(options.modifiable)
      assert.equal("hide", options.bufhidden)
      assert.equal("nofile", options.buftype)
      assert.equal("Normal:Normal", options.winhighlight)
    end)

    it("captures the popup menu event callback", function()
      cmd.enable()

      assert.is_true(cmd.is_active())
      assert.is_function(ui_callback)
    end)

    it("saves window state", function()
      local states = { [1] = { height = 50, buf = 2, view = {} } }

      helper.stub_method(util, "get_window_states", function()
        return states
      end)

      cmd.enable()

      assert.equal(states, state.win_states)
    end)

    it("registers the autotrigger mapping", function()
      config.cmd.autotrigger = true

      cmd.enable()

      assert
        .spy(vim_keymap.set)
        .called_with("c", "<C-y>", match.is_function(), match.is_table())
    end)

    it("does not register the autotrigger mapping when disabled", function()
      config.cmd.autotrigger = false

      cmd.enable()

      assert.spy(vim_keymap.set).called_at_most(0)
    end)
  end)

  describe("popup menu events", function()
    before_each(function()
      cmd.enable()
    end)

    it("renders popupmenu_show items", function()
      local items = {
        { "foo" },
        { "bar", "", "[F]" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " foo", hl = "Normal" },
        },
        {
          { text = " bar", hl = "Normal" },
          { text = " - [F]", hl = "Comment" },
        },
      })
    end)

    it("uses command definitions for command completion", function()
      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {
          write = {
            definition = "Write buffer to disk",
          },
          quit = {
            definition = "Quit the editor",
          },
        }
      end)

      cmd.disable()
      cmd.enable()

      ui_callback("popupmenu_show", {
        { "write" },
        { "quit" },
        { "other" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " write", hl = "Normal" },
          { text = " - Write buffer to disk", hl = "Comment" },
        },
        {
          { text = " quit", hl = "Normal" },
          { text = " - Quit the editor", hl = "Comment" },
        },
        {
          { text = " other", hl = "Normal" },
        },
      })
    end)

    it("does not overwrite an existing info field", function()
      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {
          write = {
            definition = "Command definition",
          },
        }
      end)

      cmd.disable()
      cmd.enable()

      local items = {
        { "write", "", "", "Existing info" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.equal("Existing info", items[1][4])
      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " write", hl = "Normal" },
          { text = " - Existing info", hl = "Comment" },
        },
      })
    end)

    it("prefers menu over info when formatting an item", function()
      ui_callback("popupmenu_show", {
        { "foo", "", "Function", "Detailed information" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " foo", hl = "Normal" },
          { text = " - Function", hl = "Comment" },
        },
      })
    end)

    it("uses info when menu is absent", function()
      ui_callback("popupmenu_show", {
        { "foo", "", "", "Detailed information" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " foo", hl = "Normal" },
          { text = " - Detailed information", hl = "Comment" },
        },
      })
    end)

    it("uses an empty string when the completion word is missing", function()
      ui_callback("popupmenu_show", {
        {},
      }, 0)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, {
        {
          { text = " ", hl = "Normal" },
        },
      })
    end)

    it("does not enrich non-command completion", function()
      helper.stub_method(vim_fn, "getcmdtype", function()
        return "/"
      end)

      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {
          write = {
            definition = "Write buffer to disk",
          },
        }
      end)

      cmd.disable()
      cmd.enable()

      local items = {
        { "write" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.is_nil(items[1][4])
    end)

    it("does not enrich command arguments", function()
      helper.stub_method(vim_fn, "getcmdline", function()
        return "write "
      end)

      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {
          write = {
            definition = "Write buffer to disk",
          },
        }
      end)

      cmd.disable()
      cmd.enable()

      local items = {
        { "write" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.is_nil(items[1][4])
    end)

    it("does not enrich unknown commands", function()
      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {}
      end)

      cmd.disable()
      cmd.enable()

      local items = {
        { "unknown" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.is_nil(items[1][4])
    end)

    it("does not enrich an empty word", function()
      helper.stub_method(vim_api, "nvim_get_commands", function()
        return {
          write = {
            definition = "Write buffer to disk",
          },
        }
      end)

      cmd.disable()
      cmd.enable()

      local items = {
        { "" },
      }

      ui_callback("popupmenu_show", items, 0)

      assert.is_nil(items[1][4])
    end)

    it("sets the selected completion extmark", function()
      ui_callback("popupmenu_show", {
        { "foo" },
        { "bar" },
      }, 1)

      assert
        .stub(vim_api.nvim_buf_set_extmark)
        .called_with(buf, state.ns, 1, 0, { line_hl_group = "MinibufferSelection" })
    end)

    it("handles popupmenu_select by replacing the previous mark", function()
      ui_callback("popupmenu_show", {
        { "foo" },
        { "bar" },
      }, 0)

      vim_api.nvim_buf_set_extmark:clear()

      -- Set mark first
      ui_callback("popupmenu_select", 1)
      -- Replace mark
      ui_callback("popupmenu_select", 2)

      assert.stub(vim_api.nvim_buf_del_extmark).called_with(buf, state.ns, 10)

      assert
        .stub(vim_api.nvim_buf_set_extmark)
        .called_with(buf, state.ns, 2, 0, { line_hl_group = "MinibufferSelection" })
    end)

    it("does not set an extmark for a negative selection", function()
      vim_api.nvim_buf_set_extmark:clear()

      ui_callback("popupmenu_select", -1)

      assert.stub(vim_api.nvim_buf_set_extmark).called_at_most(0)
    end)

    it("does not set an extmark when the buffer is invalid", function()
      helper.stub_method(vim_api, "nvim_buf_is_valid", function()
        return false
      end)

      vim_api.nvim_buf_set_extmark:clear()

      ui_callback("popupmenu_select", 0)

      assert.stub(vim_api.nvim_buf_set_extmark).called_at_most(0)
    end)

    it("clears the popup on popupmenu_hide", function()
      ui_callback("popupmenu_show", {
        { "foo" },
        { "bar" },
      }, 1)

      vim_api.nvim_buf_set_lines:clear()
      util.set_win_height:clear()
      util.write_highlighted_lines:clear()

      ui_callback("popupmenu_hide")

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, -1, false, {})

      assert.stub(vim_api.nvim_buf_clear_namespace).called_with(buf, state.ns, 0, -1)

      assert.stub(util.set_win_height).called_with(win, 0)
    end)

    it("ignores events after disable", function()
      cmd.disable()

      ui_callback("popupmenu_show", {
        { "foo" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("ignores unknown events", function()
      ui_callback("popupmenu_unknown", {
        { "foo" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)
  end)

  describe("render and height handling", function()
    before_each(function()
      cmd.enable()
    end)

    it("uses the current window height when dynamic height is disabled", function()
      config.cmd.dynamic_height = false

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 5
      end)

      ui_callback("popupmenu_show", {
        { "one" },
        { "two" },
      }, 0)

      assert.stub(util.set_win_height).called_with(win, 5)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 6)
    end)

    it("shrinks to the number of items with dynamic height", function()
      config.cmd.dynamic_height = true

      ui_callback("popupmenu_show", {
        { "one" },
        { "two" },
        { "three" },
      }, 0)

      assert.stub(util.set_win_height).called_with(win, 3)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 4)
    end)

    it("respects max height", function()
      config.cmd.dynamic_height = true
      config.cmd.max_height = 2

      ui_callback("popupmenu_show", {
        { "one" },
        { "two" },
        { "three" },
        { "four" },
      }, 0)

      assert.stub(util.set_win_height).called_with(win, 2)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 3)
    end)

    it("uses 15 as the default max height", function()
      config.cmd.dynamic_height = true
      config.cmd.max_height = nil

      local items = {}
      for i = 1, 20 do
        items[i] = { tostring(i) }
      end

      ui_callback("popupmenu_show", items, 0)

      assert.stub(util.set_win_height).called_with(win, 15)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 16)
    end)

    it("renders an empty popup with height zero", function()
      ui_callback("popupmenu_show", {
        { "foo" },
      }, 0)

      util.set_win_height:clear()
      util.set_cmdheight:clear()
      vim_api.nvim_buf_set_lines:clear()
      vim_api.nvim_buf_clear_namespace:clear()

      ui_callback("popupmenu_show", {}, -1)

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, -1, false, {})
      assert.stub(vim_api.nvim_buf_clear_namespace).called_with(buf, state.ns, 0, -1)
      assert.stub(util.set_win_height).called_with(win, 0)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 1)
    end)

    it("does nothing when the display window is invalid", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function()
        return false
      end)

      ui_callback("popupmenu_show", {
        { "foo" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_at_most(0)
      assert.stub(util.set_win_height).called_at_most(0)
    end)

    it("does nothing when the display buffer is invalid", function()
      helper.stub_method(vim_api, "nvim_buf_is_valid", function()
        return false
      end)

      ui_callback("popupmenu_show", {
        { "foo" },
      }, 0)

      assert.stub(util.write_highlighted_lines).called_at_most(0)
      assert.stub(util.set_win_height).called_at_most(0)
    end)
  end)

  describe(".disable", function()
    it("does nothing when inactive", function()
      cmd.disable()

      assert.stub(vim_ui_detach).called_at_most(0)
      assert.stub(vim_api.nvim_win_close).called_at_most(0)
      assert.stub(vim_api.nvim_buf_delete).called_at_most(0)
    end)

    it("detaches the UI", function()
      cmd.enable()
      cmd.disable()

      assert.stub(vim_ui_detach).called_with(state.ns)
    end)

    it("closes the completion window and deletes the buffer", function()
      cmd.enable()
      cmd.disable()

      assert.stub(vim_api.nvim_win_close).called_with(win, true)
      assert.stub(vim_api.nvim_buf_delete).called_with(buf, { force = true })
    end)

    it("resets its state", function()
      cmd.enable()

      ui_callback("popupmenu_show", {
        { "foo" },
      }, 0)

      cmd.disable()

      assert.is_false(cmd.is_active())
    end)

    it("restores command height", function()
      cmd.enable()
      cmd.disable()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize)
    end)

    it("removes the autotrigger mapping", function()
      config.cmd.autotrigger = true

      cmd.disable()

      vim_keymap.del:clear()

      cmd.enable()
      cmd.disable()

      assert.stub(vim_keymap.del).called_with("c", "<C-y>")
    end)
  end)

  describe(".update_cmdheight", function()
    it("does nothing when inactive", function()
      cmd.update_cmdheight()

      assert.stub(util.set_cmdheight).called_at_most(0)
    end)

    it("restores the stored command height", function()
      cmd.enable()

      ui_callback("popupmenu_show", {
        { "foo" },
        { "bar" },
      }, 0)

      util.set_cmdheight:clear()

      cmd.update_cmdheight()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 3)
    end)

    it("uses a minimum command height of one", function()
      cmd.enable()

      util.set_cmdheight:clear()

      cmd.update_cmdheight()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 1)
    end)
  end)

  describe(".cleanup", function()
    it("restores window states when present", function()
      local states = { [1] = { height = 20, buf = 1, view = {} } }
      state.win_states = states

      cmd.cleanup()

      assert.stub(util.restore_window_states).called_with(states)
      assert.stub(state.cleanup).called_at_least(1)
    end)

    it("does not restore window states when absent", function()
      state.win_states = nil

      cmd.cleanup()

      assert.stub(util.restore_window_states).called_at_most(0)
      assert.stub(state.cleanup).called_at_least(1)
    end)
  end)

  describe(".is_active", function()
    it("returns false initially", function()
      assert.is_false(cmd.is_active())
    end)

    it("returns true after enable", function()
      cmd.enable()

      assert.is_true(cmd.is_active())
    end)

    it("returns false after disable", function()
      cmd.enable()
      cmd.disable()

      assert.is_false(cmd.is_active())
    end)
  end)

  describe("autotrigger mapping", function()
    it("returns the original key when wildmenu is inactive", function()
      config.cmd.autotrigger = true
      cmd.enable()

      local callback = vim_keymap.set.calls[1].refs[3]

      helper.stub_method(vim_fn, "wildmenumode", function()
        return 0
      end)

      assert.equal("<C-y>", callback())
    end)

    it("feeds the key and returns an empty string when wildmenu is active", function()
      config.cmd.autotrigger = true
      cmd.enable()

      local feedkeys = spy.new(function() end)
      vim_api.nvim_feedkeys = feedkeys

      helper.stub_method(vim_fn, "wildmenumode", function()
        return 1
      end)

      local callback = vim_keymap.set.calls[1].refs[3]

      assert.equal("", callback())
      assert.spy(feedkeys).called_with("<C-y>", "n", false)
    end)

    it("triggers the next completion while still in command mode", function()
      config.cmd.autotrigger = true
      cmd.enable()

      local feedkeys = spy.new(function() end)
      vim_api.nvim_feedkeys = feedkeys

      helper.stub_method(vim_fn, "wildmenumode", function()
        return 1
      end)

      vim_fn.wildtrigger:clear()

      local callback = vim_keymap.set.calls[1].refs[3]
      callback()

      assert.stub(vim_fn.wildtrigger).called_at_least(1)
    end)

    it("does not trigger completion after the session becomes inactive", function()
      config.cmd.autotrigger = true
      cmd.enable()

      vim_api.nvim_feedkeys = spy.new(function() end)

      helper.stub_method(vim_fn, "wildmenumode", function()
        return 1
      end)

      vim_fn.wildtrigger:clear()

      local callback = vim_keymap.set.calls[1].refs[3]
      callback()

      cmd.disable()

      vim_fn.wildtrigger:clear()

      vim.schedule(function() end)

      assert.stub(vim_fn.wildtrigger).called_at_most(0)
    end)

    it("does not trigger completion outside command-line mode", function()
      config.cmd.autotrigger = true
      cmd.enable()

      vim_api.nvim_feedkeys = spy.new(function() end)

      helper.stub_method(vim_fn, "wildmenumode", function()
        return 1
      end)

      helper.stub_method(vim_fn, "mode", function()
        return "n"
      end)

      vim_fn.wildtrigger:clear()

      local callback = vim_keymap.set.calls[1].refs[3]
      callback()

      assert.stub(vim_fn.wildtrigger).called_at_most(0)
    end)
  end)
end)
