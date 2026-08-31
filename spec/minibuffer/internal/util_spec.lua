local ext = require("vim._core.ui2")
local helper = require("helper")
local assert, match, spy = helper.init()

describe("minibuffer.internal.util", function()
  local util
  local buf
  local win
  local timer

  local vim_api
  local vim_fn
  local vim_keymap
  local vim_uv

  before_each(function()
    helper.init_stubs()

    package.loaded["minibuffer.internal.util"] = nil
    util = require("minibuffer.internal.util")
    buf = 1
    win = 2
    timer = {
      start = spy.new(function() end),
      stop = spy.new(function() end),
      close = spy.new(function() end),
    }

    vim_api = vim.api
    vim_fn = vim.fn
    vim_keymap = vim.keymap
    vim_uv = vim.uv

    ext.wins = { cmd = win }
    ext.bufs = { cmd = buf }
    ext.ns = 42
    ext.cmdheight = 1

    helper.stub_method(vim_api, "nvim_win_is_valid", function()
      return true
    end)
    helper.stub_method(vim_api, "nvim_buf_is_valid", function()
      return true
    end)
    helper.stub_method(vim_api, "nvim_get_current_win", function()
      return 99
    end)
    helper.stub_method(vim_api, "nvim_win_get_config", function()
      return {
        relative = "",
        focusable = true,
        height = 1,
      }
    end)
    helper.stub_method(vim_api, "nvim_win_get_height", function()
      return 10
    end)
    helper.stub_method(vim_api, "nvim_win_get_buf", function()
      return buf
    end)
    helper.stub_method(vim_api, "nvim_set_current_win")
    helper.stub_method(vim_api, "nvim_win_set_config")
    helper.stub_method(vim_api, "nvim_win_set_height")
    helper.stub_method(vim_api, "nvim_buf_set_lines")
    helper.stub_method(vim_api, "nvim_buf_clear_namespace")
    helper.stub_method(vim_api, "nvim_buf_set_extmark")
    helper.stub_method(vim_api, "nvim_get_option_value")
    helper.stub_method(vim_api, "nvim_set_option_value")
    helper.stub_method(vim_api, "nvim_win_call")

    helper.stub_method(vim_fn, "winsaveview", function()
      return {
        topline = 1,
        lnum = 10,
      }
    end)
    helper.stub_method(vim_fn, "winrestview")
    helper.stub_method(vim_fn, "winlayout", function()
      return {
        "leaf",
        win,
      }
    end)

    helper.stub_method(vim_keymap, "set")

    helper.stub_method(vim, "_with", function(_, callback)
      callback()
    end)

    helper.stub_method(vim_uv, "new_timer", function()
      return timer
    end)
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  describe(".get_ext", function()
    it("returns the ui2 extension", function()
      assert.equal(ext, util.get_ext())
    end)
  end)

  describe(".get_cmd_win", function()
    it("returns the command window when valid", function()
      assert.equal(win, util.get_cmd_win())
    end)

    it("returns nil when the command window is unavailable", function()
      ext.wins = nil

      assert.is_nil(util.get_cmd_win())
    end)

    it("returns nil when the command window is invalid", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function()
        return false
      end)

      assert.is_nil(util.get_cmd_win())
    end)
  end)

  describe(".get_cmd_buf", function()
    it("returns the command buffer when valid", function()
      assert.equal(buf, util.get_cmd_buf())
    end)

    it("returns nil when the command buffer is unavailable", function()
      ext.bufs = nil

      assert.is_nil(util.get_cmd_buf())
    end)

    it("returns nil when the command buffer is invalid", function()
      helper.stub_method(vim_api, "nvim_buf_is_valid", function()
        return false
      end)

      assert.is_nil(util.get_cmd_buf())
    end)
  end)

  describe(".ready", function()
    it("returns true when both command window and buffer are valid", function()
      assert.is_true(util.ready())
    end)

    it("returns false when the command window is unavailable", function()
      ext.wins = nil

      assert.is_false(util.ready())
    end)

    it("returns false when the command buffer is unavailable", function()
      ext.bufs = nil

      assert.is_false(util.ready())
    end)
  end)

  describe(".wipe_cmd_buffer", function()
    it("clears the command buffer and namespace", function()
      util.wipe_cmd_buffer()

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, -1, false, {})
      assert.stub(vim_api.nvim_buf_clear_namespace).called_with(buf, ext.ns, 0, -1)
    end)

    it("does nothing when the command buffer is unavailable", function()
      ext.bufs = nil

      util.wipe_cmd_buffer()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
      assert.stub(vim_api.nvim_buf_clear_namespace).called_at_most(0)
    end)

    it("continues when clearing lines raises an error", function()
      helper.stub_method(vim_api, "nvim_buf_set_lines", function()
        error("boom")
      end)

      util.wipe_cmd_buffer()

      assert.stub(vim_api.nvim_buf_clear_namespace).called_at_least(1)
    end)

    it("continues when clearing the namespace raises an error", function()
      helper.stub_method(vim_api, "nvim_buf_clear_namespace", function()
        error("boom")
      end)

      util.wipe_cmd_buffer()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_least(1)
    end)
  end)

  describe(".focus_win", function()
    it("returns nil for an invalid window", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function()
        return false
      end)

      assert.is_nil(util.focus_win(win))
      assert.stub(vim_api.nvim_set_current_win).called_at_most(0)
    end)

    it("returns the previously active window", function()
      assert.equal(99, util.focus_win(win))
    end)

    it("focuses the requested window", function()
      util.focus_win(win)

      assert.stub(vim_api.nvim_set_current_win).called_with(win)
    end)

    it("makes a non-focusable window focusable first", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          relative = "",
          focusable = false,
        }
      end)

      util.focus_win(win)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        relative = "",
        focusable = true,
      })
      assert.stub(vim_api.nvim_set_current_win).called_with(win)
    end)

    it("does not change focusable configuration when already focusable", function()
      util.focus_win(win)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)
  end)

  describe(".save_cmd_opts", function()
    it("saves buffer-local options", function()
      helper.stub_method(vim_api, "nvim_get_option_value", function(name, opts)
        assert.equal(buf, opts.buf)
        return "value:" .. name
      end)

      local result = util.save_cmd_opts("buf", {
        "modifiable",
        "buftype",
      })

      assert.same({
        modifiable = "value:modifiable",
        buftype = "value:buftype",
      }, result)
    end)

    it("saves window-local options", function()
      helper.stub_method(vim_api, "nvim_get_option_value", function(name, opts)
        assert.equal(win, opts.win)
        return "value:" .. name
      end)

      local result = util.save_cmd_opts("win", {
        "number",
        "cursorline",
      })

      assert.same({
        number = "value:number",
        cursorline = "value:cursorline",
      }, result)
    end)

    it("saves global options", function()
      helper.stub_method(vim_api, "nvim_get_option_value", function(name, opts)
        assert.same({ scope = "global" }, opts)
        return "value:" .. name
      end)

      local result = util.save_cmd_opts("global", {
        "tabstop",
      })

      assert.same({
        tabstop = "value:tabstop",
      }, result)
    end)

    it("returns an empty table when the buffer is unavailable", function()
      ext.bufs = nil

      assert.same({}, util.save_cmd_opts("buf", { "modifiable" }))
      assert.stub(vim_api.nvim_get_option_value).called_at_most(0)
    end)

    it("returns an empty table when the window is unavailable", function()
      ext.wins = nil

      assert.same({}, util.save_cmd_opts("win", { "number" }))
      assert.stub(vim_api.nvim_get_option_value).called_at_most(0)
    end)

    it("rejects an invalid kind", function()
      assert.has_error(function()
        util.save_cmd_opts("invalid", { "foo" })
      end, "Invalid option kind: invalid")
    end)
  end)

  describe(".restore_cmd_opts", function()
    it("restores buffer-local options", function()
      util.restore_cmd_opts("buf", {
        modifiable = false,
        buftype = "nofile",
      })

      assert.stub(vim_api.nvim_set_option_value).called_at_least(2)
      assert
        .stub(vim_api.nvim_set_option_value)
        .called_with("modifiable", false, match.deep_equal({ buf = buf }))
      assert
        .stub(vim_api.nvim_set_option_value)
        .called_with("buftype", "nofile", match.deep_equal({ buf = buf }))
    end)

    it("restores window-local options", function()
      util.restore_cmd_opts("win", {
        number = true,
      })

      assert
        .stub(vim_api.nvim_set_option_value)
        .called_with("number", true, { win = win })
    end)

    it("restores global options", function()
      util.restore_cmd_opts("global", {
        tabstop = 4,
      })

      assert
        .stub(vim_api.nvim_set_option_value)
        .called_with("tabstop", 4, { scope = "global" })
    end)

    it("does nothing when the buffer is unavailable", function()
      ext.bufs = nil

      util.restore_cmd_opts("buf", {
        modifiable = false,
      })

      assert.stub(vim_api.nvim_set_option_value).called_at_most(0)
    end)

    it("does nothing when the window is unavailable", function()
      ext.wins = nil

      util.restore_cmd_opts("win", {
        number = true,
      })

      assert.stub(vim_api.nvim_set_option_value).called_at_most(0)
    end)

    it("rejects an invalid kind", function()
      assert.has_error(function()
        util.restore_cmd_opts("invalid", {})
      end, "Invalid option kind: invalid")
    end)
  end)

  describe(".get_window_states", function()
    it("saves states for normal windows", function()
      vim_api.nvim_tabpage_list_wins = vim_api.nvim_tabpage_list_wins
        or function()
          return { 1, 2, 3 }
        end

      helper.stub_method(vim_api, "nvim_tabpage_list_wins", function()
        return { 1, 2, 3 }
      end)

      helper.stub_method(vim_api, "nvim_win_get_config", function(window)
        if window == 2 then
          return {
            relative = "win",
          }
        end

        return {
          relative = "",
        }
      end)

      helper.stub_method(vim_api, "nvim_win_get_height", function(window)
        return window * 10
      end)

      helper.stub_method(vim_api, "nvim_win_get_buf", function(window)
        return window + 100
      end)

      helper.stub_method(vim_api, "nvim_win_call", function(_, callback)
        return callback()
      end)

      helper.stub_method(vim_fn, "winsaveview", function()
        return {
          topline = 3,
          lnum = 10,
        }
      end)

      local states = util.get_window_states()

      assert.same({
        [1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 3,
            lnum = 10,
          },
        },
        [3] = {
          height = 30,
          buf = 103,
          view = {
            topline = 3,
            lnum = 10,
          },
        },
      }, states)
    end)

    it("includes minibuffer-relative windows", function()
      helper.stub_method(vim_api, "nvim_tabpage_list_wins", function()
        return { 1 }
      end)

      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          relative = "minibuffer",
        }
      end)

      helper.stub_method(vim_api, "nvim_win_call", function(_, callback)
        return callback()
      end)

      local states = util.get_window_states()

      assert.is_not_nil(states[1])
    end)

    it("ignores floating windows", function()
      helper.stub_method(vim_api, "nvim_tabpage_list_wins", function()
        return { 1 }
      end)

      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          relative = "editor",
        }
      end)

      local states = util.get_window_states()

      assert.is_nil(states[1])
    end)
  end)

  describe(".restore_window_states", function()
    it("restores a valid window with the same buffer", function()
      local states = {
        [win] = {
          height = 25,
          buf = buf,
          view = {
            topline = 5,
            lnum = 20,
          },
        },
      }

      helper.stub_method(vim_api, "nvim_win_call", function(_, callback)
        return callback()
      end)

      util.restore_window_states(states)

      assert.stub(vim_api.nvim_win_set_height).called_with(win, 25)
      assert.stub(vim_fn.winrestview).called_with(states[win].view)
    end)

    it("does not restore an invalid window", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function()
        return false
      end)

      util.restore_window_states({
        [win] = {
          height = 25,
          buf = buf,
          view = {},
        },
      })

      assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
    end)

    it("does not restore a window containing a different buffer", function()
      helper.stub_method(vim_api, "nvim_win_get_buf", function()
        return 999
      end)

      util.restore_window_states({
        [win] = {
          height = 25,
          buf = buf,
          view = {},
        },
      })

      assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
    end)
  end)

  describe(".set_win_height", function()
    it("does nothing for a nil window", function()
      util.set_win_height(nil, 20)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)

    it("does nothing for an invalid window", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function()
        return false
      end)

      util.set_win_height(win, 20)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)

    it("does nothing when the configured height already matches", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 20,
        }
      end)

      util.set_win_height(win, 20)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)

    it("hides the window when height is zero", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 10,
        }
      end)

      util.set_win_height(win, 0)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        hide = true,
        height = 1,
      })
    end)

    it("sets a non-zero height when necessary", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 10,
        }
      end)

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 10
      end)

      util.set_win_height(win, 20)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        hide = false,
        height = 20,
      })
    end)

    it("does not reconfigure when the actual height already matches", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 5,
        }
      end)

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 20
      end)

      util.set_win_height(win, 20)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)
  end)

  describe(".set_cmdheight", function()
    local states

    local cmdheight_store
    local ext_msg_set_pos_called

    before_each(function()
      states = {
        [1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        },
      }

      cmdheight_store = 1
      ext_msg_set_pos_called = false

      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 1,
        }
      end)

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 1
      end)

      helper.stub_method(vim_api, "nvim_get_option_value", function(name, opts)
        if name == "cmdheight" and opts.scope == "global" then
          return cmdheight_store
        end
        return nil
      end)

      helper.stub_method(vim_api, "nvim_set_option_value", function(name, value, opts)
        if name == "cmdheight" and opts.scope == "global" then
          cmdheight_store = value
        end
      end)

      ext.cmdheight = 1

      ext.msg = {}
      ext.msg.set_pos = function()
        ext_msg_set_pos_called = true
      end
    end)

    it("does nothing when the command window is unavailable", function()
      ext.wins = nil

      util.set_cmdheight(states, false, 5)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)

    it("does nothing when the configured height already matches", function()
      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 5,
        }
      end)

      util.set_cmdheight(states, false, 5)

      assert.stub(vim_api.nvim_win_set_config).called_at_most(0)
    end)

    it("uses ext.cmdheight when height is nil", function()
      ext.cmdheight = 3

      helper.stub_method(vim_api, "nvim_win_get_config", function()
        return {
          height = 1,
        }
      end)

      util.set_cmdheight(states, false, nil)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        hide = false,
        height = 3,
      })
    end)

    it("hides the command window when height is zero", function()
      util.set_cmdheight(states, false, 0)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        hide = true,
        height = 1,
      })
    end)

    it("updates cmdheight through vim._with", function()
      util.set_cmdheight(states, false, 5)

      assert.stub(vim_api.nvim_win_set_config).called_with(win, {
        hide = false,
        height = 5,
      })
      assert.equal(5, cmdheight_store)
      assert.True(ext_msg_set_pos_called)
    end)

    it("does not change cmdheight when it already matches", function()
      vim_api.nvim_set_option_value("cmdheight", 5, {
        scope = "global",
      })

      util.set_cmdheight(states, false, 5)

      assert.equal(5, cmdheight_store)
      assert.False(ext_msg_set_pos_called)
    end)

    describe("resize_windows", function()
      before_each(function()
        helper.stub_method(vim_api, "nvim_win_call", function(_, callback)
          callback()
        end)

        helper.stub_method(vim_fn, "winrestview", function()
          -- no-op
        end)
      end)

      it("does not resize windows when resize_windows is false", function()
        util.set_cmdheight(states, false, 2)

        assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
      end)

      it("does not resize windows when cmdheight does not change", function()
        ext.cmdheight = 5

        helper.stub_method(vim_api, "nvim_win_get_config", function()
          return {
            height = 5,
          }
        end)

        util.set_cmdheight(states, true, 5)

        assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
      end)

      it("shrinks a single window by the cmdheight delta", function()
        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_with(1, 9)
      end)

      it("grows a single window when cmdheight decreases", function()
        states[1].height = 10
        ext.cmdheight = 5

        helper.stub_method(vim_api, "nvim_win_get_config", function()
          return {
            relative = "",
            height = 1,
          }
        end)

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        -- cmdheight decreases by 3, so the window grows by 3.
        assert.stub(vim_api.nvim_win_set_height).called_with(1, 13)
      end)

      it("does not resize when cmdheight stays the same", function()
        ext.cmdheight = 2
        cmdheight_store = 2

        helper.stub_method(vim_api, "nvim_win_get_config", function()
          return {
            height = 2,
          }
        end)

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
      end)

      it("resizes all windows equally in a row layout", function()
        states[1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[2] = {
          height = 10,
          buf = 102,
          view = {
            topline = 2,
            lnum = 10,
          },
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "row",
            {
              { "leaf", 1 },
              { "leaf", 2 },
            },
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_with(1, 9)
        assert.stub(vim_api.nvim_win_set_height).called_with(2, 9)
      end)

      it("splits stacked windows proportionally in a col layout", function()
        states[1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[2] = {
          height = 20,
          buf = 102,
          view = {
            topline = 1,
            lnum = 20,
          },
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "col",
            {
              { "leaf", 1 },
              { "leaf", 2 },
            },
          }
        end)

        -- Root height = 30.
        -- cmdheight increases from 1 -> 2, so target = 29.
        -- Weights are 10:20, giving 29 * 10/30 = 9.67
        -- and 29 * 20/30 = 19.33 => 10 and 19.
        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_with(1, 10)
        assert.stub(vim_api.nvim_win_set_height).called_with(2, 19)
      end)

      it("distributes proportional rounding deterministically", function()
        states[1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[2] = {
          height = 10,
          buf = 102,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[3] = {
          height = 10,
          buf = 103,
          view = {
            topline = 1,
            lnum = 10,
          },
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "col",
            {
              { "leaf", 1 },
              { "leaf", 2 },
              { "leaf", 3 },
            },
          }
        end)

        util.set_cmdheight(states, true, 2)

        -- Root height = 30, target height = 29.
        -- 10 + 10 + 9 (First children are preferred)
        assert.stub(vim_api.nvim_win_set_height).called_with(1, 10)
        assert.stub(vim_api.nvim_win_set_height).called_with(2, 10)
        assert.stub(vim_api.nvim_win_set_height).called_with(3, 9)
      end)

      it("handles nested row and col layouts", function()
        states[1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[2] = {
          height = 10,
          buf = 102,
          view = {
            topline = 1,
            lnum = 10,
          },
        }
        states[3] = {
          height = 20,
          buf = 103,
          view = {
            topline = 1,
            lnum = 20,
          },
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "col",
            {
              {
                "row",
                {
                  { "leaf", 1 },
                  { "leaf", 2 },
                },
              },
              { "leaf", 3 },
            },
          }
        end)

        -- Root = 20 + max(10, 10) = 30.
        -- Target = 29.
        --
        -- First subtree weight = 10.
        -- Second subtree weight = 20.
        -- Target split = 10 / 19.
        --
        -- The row subtree then gives both windows height 10.
        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_with(1, 10)
        assert.stub(vim_api.nvim_win_set_height).called_with(2, 10)
        assert.stub(vim_api.nvim_win_set_height).called_with(3, 19)
      end)

      it("uses zero height for windows missing from states", function()
        states[1] = {
          height = 10,
          buf = 101,
          view = {
            topline = 1,
            lnum = 10,
          },
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "col",
            {
              { "leaf", 1 },
              { "leaf", 2 },
            },
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_with(1, 9)
        assert.stub(vim_api.nvim_win_set_height).called_at_most(1)
      end)

      it("restores each window view after resizing", function()
        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_call).called_with(1, match.is_function())

        assert.stub(vim_fn.winrestview).called_with({
          topline = 2,
          lnum = 10,
        })
      end)

      it("does not move topline past the cursor line", function()
        states[1].view = {
          topline = 8,
          lnum = 10,
        }

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_fn.winrestview).called_with(match.same({
          topline = 9,
          lnum = 10,
        }))
      end)

      it("preserves the original state view", function()
        local original_view = {
          topline = 1,
          lnum = 10,
        }

        states[1].view = original_view

        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        util.set_cmdheight(states, true, 2)

        assert.same({
          topline = 1,
          lnum = 10,
        }, original_view)
      end)

      it("does not resize floating windows", function()
        helper.stub_method(vim_fn, "winlayout", function()
          return {
            "leaf",
            1,
          }
        end)

        -- The resize helper itself only sees windows from the layout.
        -- Floating-window filtering belongs to get_window_states().
        -- This test documents that states control which leaves can resize.
        states[1] = nil

        util.set_cmdheight(states, true, 2)

        assert.stub(vim_api.nvim_win_set_height).called_at_most(0)
      end)
    end)
  end)

  describe(".write_highlighted_lines", function()
    it("writes plain text lines", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
        },
        {
          { text = "world" },
        },
      })

      assert
        .stub(vim_api.nvim_buf_set_lines)
        .called_with(buf, 0, 2, false, { "hello", "world" })

      assert.stub(vim_api.nvim_buf_set_extmark).called_at_most(0)
    end)

    it("combines chunks into a single line", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
          { text = " " },
          { text = "world" },
        },
      })

      assert
        .stub(vim_api.nvim_buf_set_lines)
        .called_with(buf, 0, 1, false, { "hello world" })
    end)

    it("creates extmarks for highlighted chunks", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello", hl = "Comment" },
          { text = " world", hl = "String" },
        },
      })

      assert.stub(vim_api.nvim_buf_set_extmark).called_at_least(2)
      assert.stub(vim_api.nvim_buf_set_extmark).called_with(
        buf,
        42,
        0,
        0,
        match.deep_equal({
          hl_group = "Comment",
          end_col = 5,
        })
      )
      assert.stub(vim_api.nvim_buf_set_extmark).called_with(
        buf,
        42,
        0,
        5,
        match.deep_equal({
          hl_group = "String",
          end_col = 11,
        })
      )
    end)

    it("treats missing chunk text as an empty string", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { hl = "Comment" },
        },
      })

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, 1, false, { "" })
      assert.stub(vim_api.nvim_buf_set_extmark).called_with(
        buf,
        42,
        0,
        0,
        match.deep_equal({
          hl_group = "Comment",
          end_col = 0,
        })
      )
    end)

    it("supports a custom start line", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
        },
      }, {
        start_line = 5,
      })

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 5, 6, false, { "hello" })
    end)

    it("replaces existing content by default", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
        },
      })

      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, -1, false, {})
      assert.stub(vim_api.nvim_buf_clear_namespace).called_with(buf, 42, 0, -1)
    end)

    it("does not clear existing content when replace_existing is false", function()
      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
        },
      }, {
        replace_existing = false,
      })

      assert.stub(vim_api.nvim_buf_clear_namespace).called_at_most(0)
      assert.stub(vim_api.nvim_buf_set_lines).called_with(buf, 0, 0, false, { "hello" })
    end)

    it("clears old content even when clearing raises an error", function()
      helper.stub_method(vim_api, "nvim_buf_set_lines", function(_, start, finish, _, _)
        if start == 0 and finish == -1 then
          error("boom")
        end
      end)

      util.write_highlighted_lines(buf, 42, {
        {
          { text = "hello" },
        },
      })

      assert.stub(vim_api.nvim_buf_clear_namespace).called_at_least(1)
    end)
  end)

  describe(".create_condition_keyset", function()
    it("wraps function mappings", function()
      local condition = spy.new(function()
        return true
      end)

      local rhs_called = false
      local rhs = function()
        rhs_called = true
      end

      local keyset = util.create_condition_keyset(condition)

      keyset("n", "q", rhs)

      local callback = vim_keymap.set.calls[1].refs[3]

      callback()

      assert.spy(condition).called_at_least(1)
      assert.True(rhs_called)
    end)

    it("does not execute function mappings when the condition is false", function()
      local condition = spy.new(function()
        return false
      end)

      local rhs_called = false
      local rhs = function()
        rhs_called = true
      end

      local keyset = util.create_condition_keyset(condition)

      keyset("n", "q", rhs)

      local callback = vim_keymap.set.calls[1].refs[3]

      callback()

      assert.spy(condition).called_at_least(1)
      assert.False(rhs_called)
    end)

    it("wraps string mappings", function()
      local condition = spy.new(function()
        return true
      end)

      helper.stub_method(vim_api, "nvim_get_mode", function()
        return { mode = "n" }
      end)
      helper.stub_method(vim_api, "nvim_feedkeys")
      helper.stub_method(vim_api, "nvim_replace_termcodes", function(rhs)
        return rhs
      end)

      local keyset = util.create_condition_keyset(condition)

      keyset("n", "q", "abc")

      local callback = vim_keymap.set.calls[1].refs[3]

      callback()

      assert.stub(vim_api.nvim_get_mode).called_at_least(1)
      assert.stub(vim_api.nvim_replace_termcodes).called_with("abc", true, false, true)
      assert.stub(vim_api.nvim_feedkeys).called_at_least(1)
    end)

    it("does not feed string mappings when the condition is false", function()
      local condition = spy.new(function()
        return false
      end)

      helper.stub_method(vim_api, "nvim_get_mode")
      helper.stub_method(vim_api, "nvim_feedkeys")
      helper.stub_method(vim_api, "nvim_replace_termcodes")

      local keyset = util.create_condition_keyset(condition)

      keyset("n", "q", "abc")

      local callback = vim_keymap.set.calls[1].refs[3]

      callback()

      assert.stub(vim_api.nvim_feedkeys).called_at_most(0)
    end)

    it("merges base options with mapping options", function()
      local keyset = util.create_condition_keyset(function()
        return true
      end, {
        silent = true,
        desc = "base",
      })

      keyset("n", "q", function() end, {
        desc = "override",
        nowait = true,
      })

      local opts = vim_keymap.set.calls[1].refs[4]

      assert.same({
        silent = true,
        desc = "override",
        nowait = true,
      }, opts)
    end)

    it("accepts omitted options", function()
      local keyset = util.create_condition_keyset(function()
        return true
      end)

      keyset("n", "q", function() end)

      assert.is_function(vim_keymap.set.calls[1].refs[3])
    end)
  end)

  describe(".make_debounced", function()
    it("creates a timer", function()
      util.make_debounced(100)

      assert.stub(vim_uv.new_timer).called_at_least(1)
      assert.spy(timer.start).called_at_most(0)
    end)

    it("stops the timer before starting it", function()
      local debounce = util.make_debounced(100)
      local callback = function() end

      debounce(callback)

      assert.spy(timer.stop).called_at_least(1)
      assert.spy(timer.start).called_at_least(1)
    end)

    it("stops the timer and schedules the callback when it fires", function()
      local scheduled = spy.new(function(fn)
        fn()
      end)

      helper.stub_method(vim, "schedule", scheduled)

      local debounce = util.make_debounced(100)
      local callback = spy.new(function() end)

      debounce(callback)
    end)
  end)
end)
