local config = require("minibuffer.config")
local helper = require("helper")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")
local assert, _, spy = helper.init()

describe("minibuffer.sessions.display", function()
  local DisplaySession
  local buf
  local win
  local timer

  local vim_api
  local vim_keymap
  local vim_uv

  before_each(function()
    helper.init_stubs()

    package.loaded["minibuffer.sessions.display"] = nil
    DisplaySession = require("minibuffer.sessions.display")
    buf = 1
    win = 2
    timer = {
      start = spy.new(function() end),
      stop = spy.new(function() end),
      close = spy.new(function() end),
    }

    vim_api = vim.api
    vim_keymap = vim.keymap
    vim_uv = vim.uv

    state.session = nil
    state.active_window = nil
    state.win_states = nil
    state.ns = 1

    helper.stub_method(util, "get_cmd_buf", function()
      return buf
    end)
    helper.stub_method(util, "get_cmd_win", function()
      return win
    end)
    helper.stub_method(util, "get_window_states", function()
      return { [1] = { height = 22, buf = 1, view = {} } }
    end)
    helper.stub_method(util, "wipe_cmd_buffer")
    helper.stub_method(util, "write_highlighted_lines")
    helper.stub_method(util, "set_cmdheight")
    helper.stub_method(util, "restore_window_states")

    helper.stub_method(state, "cleanup")

    helper.stub_method(vim_api, "nvim_win_set_var")
    helper.stub_method(vim_api, "nvim_win_get_height", function()
      return 10
    end)
    helper.stub_method(vim_api, "nvim__redraw")
    helper.stub_method(vim_api, "nvim_win_is_valid", function()
      return true
    end)
    helper.stub_method(vim_api, "nvim_set_current_win")

    helper.stub_method(vim_keymap, "set")

    helper.stub_method(vim, "schedule", function(callback)
      callback()
    end)

    helper.stub_method(vim_uv, "new_timer", function()
      return timer
    end)
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  describe(".new", function()
    it("creates a closed display session with defaults", function()
      local session = DisplaySession.new()

      assert.is_true(session._closed)
      assert.same({}, session.lines)
      assert.is_nil(session.timeout)
      assert.same({ "<F5>" }, session.close_keys)
      assert.is_false(session.dynamic_height)
      assert.is_nil(session.on_close)
      assert.is_nil(session._timer)
    end)

    it("accepts all options", function()
      local on_close = function() end
      local lines = {
        { "hello", "Comment" },
        { "world", "String" },
      }

      local session = DisplaySession.new({
        lines = lines,
        timeout = 1000,
        close_keys = { "<Esc>", "q" },
        dynamic_height = true,
        on_close = on_close,
      })

      assert.same(lines, session.lines)
      assert.equal(1000, session.timeout)
      assert.same({ "<Esc>", "q" }, session.close_keys)
      assert.is_true(session.dynamic_height)
      assert.equal(on_close, session.on_close)
      assert.is_true(session._closed)
      assert.is_nil(session._timer)
    end)

    it("does not enable dynamic height unless explicitly true", function()
      assert.is_false(DisplaySession.new().dynamic_height)
      assert.is_false(DisplaySession.new({
        dynamic_height = false,
      }).dynamic_height)
    end)
  end)

  describe(":type", function()
    it("returns display", function()
      local session = DisplaySession.new()
      assert.equal("display", session:type())
    end)
  end)

  describe(":overridable", function()
    it("is overridable", function()
      local session = DisplaySession.new()
      assert.is_true(session:overridable())
    end)
  end)

  describe(":resumable", function()
    it("is not resumable", function()
      local session = DisplaySession.new()
      assert.is_false(session:resumable())
    end)
  end)

  describe(":pre_start", function()
    it("does nothing when the command buffer is unavailable", function()
      helper.stub_method(util, "get_cmd_buf", function()
        return nil
      end)

      local session = DisplaySession.new()

      session:pre_start()

      assert.is_true(session._closed)
      assert.is_nil(state.win_states)
      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
    end)

    it("does nothing when the command window is unavailable", function()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      local session = DisplaySession.new()

      session:pre_start()

      assert.is_true(session._closed)
      assert.is_nil(state.win_states)
      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
    end)

    it(
      "opens the session and saves window state, properly setting minibuffer win var",
      function()
        local states = { [1] = { height = 50, buf = 2, view = {} } }

        helper.stub_method(util, "get_window_states", function()
          return states
        end)

        local session = DisplaySession.new()

        session:pre_start()

        assert.is_false(session._closed)
        assert.equal(states, state.win_states)
        assert.stub(util.wipe_cmd_buffer).called_at_least(1)
        assert.stub(vim_api.nvim_win_set_var).called_with(win, "minibuffer", true)
      end
    )

    it("starts a timer when timeout is positive", function()
      local session = DisplaySession.new({
        timeout = 500,
      })

      session:pre_start()

      assert.equal(timer, session._timer)
      assert.spy(timer.start).called_at_least(1)

      local args = timer.start.calls[1].refs
      assert.equal(500, args[2])
      assert.equal(0, args[3])
      assert.is_function(args[4])
    end)

    it("does not start a timer for a zero timeout", function()
      local session = DisplaySession.new({
        timeout = 0,
      })

      session:pre_start()

      assert.is_nil(session._timer)
      assert.stub(vim_uv.new_timer).called_at_most(0)
    end)

    it("does not start a timer for a negative timeout", function()
      local session = DisplaySession.new({
        timeout = -1,
      })

      session:pre_start()

      assert.is_nil(session._timer)
      assert.stub(vim_uv.new_timer).called_at_most(0)
    end)
  end)

  describe(":render", function()
    it("does nothing after the session is closed", function()
      local session = DisplaySession.new()

      session:render()

      assert.stub(util.get_cmd_buf).called_at_most(0)
      assert.stub(util.write_highlighted_lines).called_at_most(0)
      assert.stub(vim_api.nvim__redraw).called_at_most(0)
    end)

    it("does nothing when the command buffer is unavailable", function()
      local session = DisplaySession.new()
      session._closed = false

      helper.stub_method(util, "get_cmd_buf", function()
        return nil
      end)

      session:render()

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("does nothing when the command window is unavailable", function()
      local session = DisplaySession.new()
      session._closed = false

      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      session:render()

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("writes the configured lines", function()
      local lines = {
        { "hello", "Comment" },
        { "world", "String" },
      }

      local session = DisplaySession.new({
        lines = lines,
      })

      session._closed = false
      state.ns = 42
      state.win_states = {}

      session:render()

      assert.stub(util.write_highlighted_lines).called_with(buf, 42, lines)
      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)

    it("uses the number of lines as the height with dynamic height", function()
      local session = DisplaySession.new({
        lines = {
          { "one" },
          { "two" },
          { "three" },
        },
        dynamic_height = true,
      })

      session._closed = false
      state.win_states = {}

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 4)
      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)

    it("does not shrink the window when dynamic height is disabled", function()
      local session = DisplaySession.new({
        lines = {
          { "one" },
          { "two" },
        },
        dynamic_height = false,
      })

      session._closed = false
      state.win_states = {}

      session:render()

      -- Existing height is 10, so 2 lines + 1 should not shrink it.
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 11)
      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)

    it("expands the window when content is taller than the current window", function()
      helper.stub_method(vim.api, "nvim_win_get_height", function()
        return 2
      end)

      local session = DisplaySession.new({
        lines = {
          { "one" },
          { "two" },
          { "three" },
          { "four" },
        },
      })

      session._closed = false
      state.win_states = {}

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 5)
      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)
  end)

  describe(":post_start", function()
    it("does nothing when the session is closed", function()
      local session = DisplaySession.new()

      session:post_start()

      assert.spy(vim_keymap.set).called_at_most(0)
    end)

    it("does nothing when the command buffer is unavailable", function()
      local session = DisplaySession.new()
      session._closed = false

      helper.stub_method(util, "get_cmd_buf", function()
        return nil
      end)

      session:post_start()

      assert.spy(vim_keymap.set).called_at_most(0)
    end)

    it("creates close mappings for every close key", function()
      local session = DisplaySession.new({
        close_keys = { "<Esc>", "q", "x" },
      })
      session._closed = false

      session:post_start()

      assert.spy(vim_keymap.set).called_at_least(3)

      local lhs = {}
      for _, call in ipairs(vim_keymap.set.calls) do
        lhs[call.refs[2]] = true
      end

      for _, key in ipairs({
        "<Esc>",
        "q",
        "x",
      }) do
        assert.is_true(lhs[key])
      end
    end)

    it("uses the expected keymap options", function()
      local session = DisplaySession.new({
        close_keys = { "q" },
      })
      session._closed = false

      session:post_start()

      local opts = vim_keymap.set.calls[1].refs[4]

      assert.same({
        buf = buf,
        nowait = true,
        silent = true,
        noremap = true,
      }, opts)
    end)

    it("closes the session when its mapping is invoked", function()
      local session = DisplaySession.new({
        close_keys = { "q" },
      })
      session._closed = false
      state.session = session

      session.close = spy.new(function()
        session._closed = true
      end)

      session:post_start()

      local callback = vim_keymap.set.calls[1].refs[3]
      callback()

      assert.spy(session.close).called_at_least(1)
    end)

    it("does not close a session that is no longer active", function()
      local session = DisplaySession.new({
        close_keys = { "q" },
      })
      session._closed = false
      state.session = DisplaySession.new()

      session.close = spy.new(function()
        session._closed = true
      end)

      session:post_start()

      local callback = vim_keymap.set.calls[1].refs[3]
      callback()

      assert.spy(session.close).called_at_most(0)
    end)
  end)

  describe(":cancel", function()
    it("does nothing when already closed", function()
      local session = DisplaySession.new()

      session.close = spy.new(function() end)
      session:cancel()

      assert.spy(session.close).called_at_most(0)
    end)

    it("closes an active session", function()
      local session = DisplaySession.new()
      session._closed = false

      session.close = spy.new(function() end)
      session:cancel()

      assert.spy(session.close).called_at_least(1)
    end)
  end)

  describe(":close", function()
    it("does nothing when already closed", function()
      local session = DisplaySession.new()

      session:close()

      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
      assert.stub(util.restore_window_states).called_at_most(0)
      assert.stub(state.cleanup).called_at_most(0)
    end)

    it("does not restore state when the command window is unavailable", function()
      local session = DisplaySession.new()
      session._closed = false

      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      session:close()

      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
      assert.stub(util.restore_window_states).called_at_most(0)
      assert.stub(state.cleanup).called_at_most(0)
    end)

    it("cleans up the session", function()
      local session = DisplaySession.new()
      session._closed = false

      session:close()

      assert.stub(vim_api.nvim_win_set_var).called_with(win, "minibuffer", nil)
      assert.stub(state.cleanup).called_at_least(1)
    end)
  end)

  describe(":update_lines", function()
    it("returns false when the session is closed", function()
      local session = DisplaySession.new()

      assert.is_false(session:update_lines({
        { "hello" },
      }))

      assert.same({}, session.lines)
    end)

    it("updates the lines of an active session", function()
      local session = DisplaySession.new()
      session._closed = false

      local lines = {
        { "hello", "String" },
        { "world", "Comment" },
      }

      session.render = spy.new(function() end)

      assert.is_true(session:update_lines(lines))
      assert.same(lines, session.lines)
      assert.spy(session.render).called_at_least(1)
    end)

    it("renders the updated lines", function()
      local session = DisplaySession.new()
      session._closed = false

      local lines = {
        { "updated" },
      }

      session:update_lines(lines)

      assert.stub(util.write_highlighted_lines).called_with(buf, state.ns, lines)
    end)
  end)
end)
