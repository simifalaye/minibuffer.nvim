local helper = require("helper")
local assert, match, spy = helper.init()

describe("minibuffer", function()
  local minibuffer
  local state
  local util
  local config
  local cmd

  local vim_api
  local vim_fn

  local session
  local current_win = 42

  local vim_notify_stub

  before_each(function()
    package.loaded["minibuffer"] = nil
    package.loaded["minibuffer.internal.state"] = nil
    package.loaded["minibuffer.internal.cmd"] = nil

    helper.init_stubs()

    state = require("minibuffer.internal.state")
    util = require("minibuffer.internal.util")
    config = require("minibuffer.config")
    cmd = require("minibuffer.internal.cmd")
    minibuffer = require("minibuffer")

    vim_api = vim.api
    vim_fn = vim.fn

    state.initialized = true
    state.session = nil
    state.prev_session = nil
    state.active_window = nil
    state.pending_render = nil
    state.win_states = nil

    session = {
      overridable = spy.new(function()
        return true
      end),
      pre_start = spy.new(function() end),
      render = spy.new(function() end),
      post_start = spy.new(function() end),
      close = spy.new(function(_, done)
        if done then
          done()
        end
      end),
    }

    helper.stub_method(util, "ready", function()
      return true
    end)

    helper.stub_method(vim_api, "nvim_get_current_win", function()
      return current_win
    end)
    helper.stub_method(vim_api, "nvim_create_autocmd")

    helper.stub_method(vim, "schedule", function(callback)
      callback()
    end)
    vim_notify_stub = helper.stub_method(vim, "notify")

    helper.stub_method(cmd, "enable")
    helper.stub_method(cmd, "disable")
    helper.stub_method(cmd, "update_cmdheight")
    helper.stub_method(cmd, "cleanup")

    helper.stub_method(vim_api, "nvim_set_hl")
    helper.stub_method(vim_api, "nvim_open_win", function()
      return 100
    end)
    helper.stub_method(vim_api, "nvim_win_set_config")
    helper.stub_method(vim_api, "nvim_win_close")

    package.loaded["minibuffer.sessions.input"] = {
      new = spy.new(function()
        return session
      end),
    }
    package.loaded["minibuffer.sessions.select"] = {
      new = spy.new(function()
        return session
      end),
    }
    package.loaded["minibuffer.sessions.display"] = {
      new = spy.new(function()
        return session
      end),
    }
    package.loaded["minibuffer.sessions.scratch"] = {
      new = spy.new(function()
        return session
      end),
    }
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  describe("session startup", function()
    it("requires initialization", function()
      state.initialized = false

      assert.has_error(function()
        minibuffer.display()
      end, "Must call `initialize()` first")
    end)

    it("returns false when the plugin is not ready", function()
      helper.stub_method(util, "ready", function()
        return false
      end)

      assert.is_false(minibuffer.display())
      assert
        .stub(vim_notify_stub)
        .called_with("[minibuffer] ext cmd buffer not ready yet.", vim.log.levels.WARN)
      assert.is_nil(state.session)
    end)

    it("rejects a non-overridable active session", function()
      local overridable = spy.new(function()
        return false
      end)
      state.session = {
        overridable = overridable,
      }

      assert.is_false(minibuffer.display())
      assert
        .stub(vim_notify_stub)
        .called_with("[minibuffer] Session active (use force=true).", vim.log.levels.INFO)
      assert.spy(overridable).called_at_least(1)
    end)

    it("allows replacing a non-overridable session with force", function()
      local close = spy.new(function(_, done)
        done()
      end)
      state.session = {
        overridable = spy.new(function()
          return false
        end),
        close = close,
      }

      assert.is_true(minibuffer.display(nil, true))
      assert.equal(session, state.session)
      assert.spy(close).called_at_least(1)
    end)

    it("starts a session when there is no active session", function()
      assert.is_true(minibuffer.display())

      assert.equal(session, state.session)
      assert.equal(current_win, state.active_window)
      assert.is_false(state.pending_render)
      assert.spy(session.pre_start).called_at_least(1)
      assert.spy(session.render).called_at_least(1)
      assert.spy(session.post_start).called_at_least(1)
    end)

    it("closes the existing session before starting the new one", function()
      local old_session = {
        overridable = spy.new(function()
          return true
        end),
        close = spy.new(function(_, done)
          done()
        end),
      }

      state.session = old_session

      assert.is_true(minibuffer.display())
      assert.spy(old_session.close).called_at_least(1)
      assert.equal(session, state.session)
      assert.spy(session.pre_start).called_at_least(1)
      assert.spy(session.render).called_at_least(1)
      assert.spy(session.post_start).called_at_least(1)
    end)

    it("waits for the old session close callback before starting", function()
      local start_close

      local old_session = {
        overridable = function()
          return true
        end,
        close = spy.new(function(_, done)
          start_close = done
        end),
      }

      state.session = old_session

      assert.is_true(minibuffer.display())
      assert.spy(session.pre_start).called_at_most(0)
      assert.equal(old_session, state.session)

      start_close()

      assert.equal(session, state.session)
      assert.spy(session.pre_start).called_at_least(1)
    end)

    it("creates a FocusLost autocmd", function()
      assert.is_true(minibuffer.display())
      assert.stub(vim_api.nvim_create_autocmd).called_with(
        "FocusLost",
        match.satisfies(function(arg)
          return arg.callback ~= nil and type(arg.callback) == "function"
        end)
      )
    end)

    it("closes the active session when FocusLost fires", function()
      assert.is_true(minibuffer.display())

      local callback = vim_api.nvim_create_autocmd.calls[1].refs[2].callback
      callback()

      assert.spy(session.close).called_at_least(1)
    end)

    it(
      "does not close anything from FocusLost when there is no active session",
      function()
        assert.is_true(minibuffer.display())

        state.session = nil

        local callback = vim_api.nvim_create_autocmd.calls[1].refs[2].callback
        callback()

        assert.spy(session.close).called_at_most(0)
      end
    )
  end)

  describe("resume", function()
    it("returns false when there is no previous session", function()
      state.prev_session = nil

      assert.is_false(minibuffer.resume())

      assert
        .stub(vim_notify_stub)
        .called_with("[minibuffer] No session available to resume.", vim.log.levels.WARN)
    end)

    it("starts the previous session", function()
      state.prev_session = session

      assert.is_true(minibuffer.resume())

      assert.equal(session, state.session)
      assert.spy(session.pre_start).called_at_least(1)
      assert.spy(session.render).called_at_least(1)
      assert.spy(session.post_start).called_at_least(1)
    end)

    it("passes force through when resuming", function()
      state.session = {
        overridable = function()
          return false
        end,
        close = function(_, done)
          done()
        end,
      }
      state.prev_session = session

      assert.is_true(minibuffer.resume(true))
      assert.equal(session, state.session)
    end)
  end)

  describe("session state accessors", function()
    it("reports whether a session is active", function()
      assert.is_false(minibuffer.is_active())

      state.session = session

      assert.is_true(minibuffer.is_active())
    end)

    it("returns the active session", function()
      assert.is_nil(minibuffer.get_active_session())

      state.session = session

      assert.equal(session, minibuffer.get_active_session())
    end)

    it("returns the active window", function()
      assert.is_nil(minibuffer.get_active_window())

      state.active_window = 123

      assert.equal(123, minibuffer.get_active_window())
    end)
  end)

  describe("initialize", function()
    it("does nothing when already initialized", function()
      state.initialized = true

      local compat = spy.new(function() end)
      package.loaded["minibuffer.internal.compat"] = {
        initialize = compat,
      }

      minibuffer.initialize()

      assert.spy(compat).called_at_most(0)
    end)

    it("initializes the compatibility layer", function()
      state.initialized = false

      local compat = spy.new(function() end)
      package.loaded["minibuffer.internal.compat"] = {
        initialize = compat,
      }

      minibuffer.initialize()

      assert.spy(compat).called_at_least(1)
      assert.is_true(state.initialized)
    end)

    it("sets up the expected highlight groups", function()
      state.initialized = false

      minibuffer.initialize()

      assert
        .stub(vim_api.nvim_set_hl)
        .called_with(0, "MinibufferPrompt", { link = "Question" })
      assert
        .stub(vim_api.nvim_set_hl)
        .called_with(0, "MinibufferSelection", { link = "Visual" })
      assert
        .stub(vim_api.nvim_set_hl)
        .called_with(0, "MinibufferMultiSelected", { link = "Search" })
      assert
        .stub(vim_api.nvim_set_hl)
        .called_with(0, "MinibufferSuggestion", { link = "Comment" })
      assert
        .stub(vim_api.nvim_set_hl)
        .called_with(0, "MinibufferLoading", { link = "Comment" })
    end)

    it("registers the ColorScheme autocmd", function()
      state.initialized = false

      minibuffer.initialize()

      assert
        .stub(vim_api.nvim_create_autocmd)
        .called_with("ColorScheme", match.is_table())
    end)

    it("reruns highlight setup on ColorScheme", function()
      state.initialized = false

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[1].refs[2].callback

      vim_api.nvim_set_hl:clear()

      callback()

      assert.stub(vim_api.nvim_set_hl).called_at_least(5)
    end)

    it("rerenders the active session on VimResized", function()
      state.initialized = false
      state.session = session

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[2].refs[2].callback
      callback()

      assert.spy(session.render).called_at_least(1)
    end)

    it("does nothing on VimResized without an active session", function()
      state.initialized = false
      state.session = nil

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[2].refs[2].callback
      callback()

      assert.spy(session.render).called_at_most(0)
    end)

    it("enables command completion on CmdlineEnter", function()
      state.initialized = false
      state.session = nil

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[3].refs[2].callback
      callback()

      assert.stub(cmd.enable).called_at_least(1)
    end)

    it("closes an active session before enabling command completion", function()
      state.initialized = false
      state.session = session

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[3].refs[2].callback
      callback()

      assert.spy(session.close).called_at_least(1)
      assert.stub(cmd.enable).called_at_least(1)
    end)

    it("disables command completion on CmdlineLeave", function()
      state.initialized = false

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[4].refs[2].callback
      callback()

      assert.stub(cmd.disable).called_at_least(1)
    end)

    it("triggers completion on CmdlineChanged when autotrigger is enabled", function()
      state.initialized = false
      config.cmd.autotrigger = true

      local wildtrigger_called = false
      helper.stub_method(vim_fn, "mode", function()
        return "c"
      end)
      helper.stub_method(vim_fn, "wildtrigger", function()
        wildtrigger_called = true
      end)

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[5].refs[2].callback
      callback()

      assert.is_true(wildtrigger_called)
    end)

    it("does not trigger completion outside command-line mode", function()
      state.initialized = false
      config.cmd.autotrigger = true

      local wildtrigger_called = false
      helper.stub_method(vim_fn, "mode", function()
        return "n"
      end)
      helper.stub_method(vim_fn, "wildtrigger", function()
        wildtrigger_called = true
      end)

      minibuffer.initialize()

      local callback = vim_api.nvim_create_autocmd.calls[5].refs[2].callback
      callback()

      assert.is_not_true(wildtrigger_called)
    end)

    it("wraps nvim_open_win for minibuffer windows", function()
      state.initialized = false

      local scratch = package.loaded["minibuffer.sessions.scratch"]
      local scratch_session = {
        overridable = spy.new(function()
          return true
        end),
        pre_start = spy.new(function() end),
        render = spy.new(function() end),
        post_start = spy.new(function() end),
        get_win = spy.new(function()
          return 100
        end),
      }
      helper.stub_method(scratch, "new", function(_)
        return scratch_session
      end)

      local opts = {
        relative = "cursor",
        width = 20,
        use_minibuffer = true,
      }

      minibuffer.initialize()

      local result = vim_api.nvim_open_win(7, true, opts)

      assert.equal(100, result)
      assert.spy(scratch.new).called_with({
        buf = 7,
        win_config = opts,
        enter = true,
      })
      assert.is_nil(opts.use_minibuffer)
      assert.spy(scratch_session.get_win).called_at_least(1)
    end)

    it("wraps nvim_open_win for relative minibuffer windows", function()
      state.initialized = false

      local scratch = package.loaded["minibuffer.sessions.scratch"]
      local scratch_session = {
        overridable = spy.new(function()
          return true
        end),
        pre_start = spy.new(function() end),
        render = spy.new(function() end),
        post_start = spy.new(function() end),
        get_win = spy.new(function()
          return 100
        end),
      }
      helper.stub_method(scratch, "new", function(_)
        return scratch_session
      end)

      local opts = {
        relative = "minibuffer",
        width = 20,
      }

      minibuffer.initialize()

      vim_api.nvim_open_win(7, false, opts)

      assert.spy(scratch.new).called_at_least(1)
      assert.is_nil(opts.use_minibuffer)
    end)

    it("returns zero when a minibuffer scratch session cannot start", function()
      state.initialized = false

      local scratch = package.loaded["minibuffer.sessions.scratch"]
      helper.stub_method(scratch, "new", function()
        return {
          overridable = function()
            return true
          end,
          pre_start = function() end,
          render = function() end,
          post_start = function() end,
        }
      end)

      helper.stub_method(util, "ready", function()
        return false
      end)

      minibuffer.initialize()

      local result = vim_api.nvim_open_win(7, false, {
        relative = "minibuffer",
      })

      assert.equal(0, result)
    end)

    it(
      "passes non-minibuffer nvim_open_win calls to the default implementation",
      function()
        state.initialized = false

        state.default_nvim_open_win = spy.new(function(_, _, _)
          return 123
        end)

        minibuffer.initialize()

        local opts = {
          relative = "cursor",
        }

        local result = vim_api.nvim_open_win(7, false, opts)

        assert.equal(123, result)
        assert.spy(state.default_nvim_open_win).called_with(7, false, opts)
      end
    )

    it("routes nvim_win_set_config to the active scratch session", function()
      state.initialized = false

      local scratch = {
        type = function()
          return "scratch"
        end,
        get_win = function()
          return 55
        end,
        set_win_config = spy.new(function() end),
      }

      state.session = scratch

      minibuffer.initialize()

      local opts = {
        width = 30,
        use_minibuffer = true,
      }

      vim_api.nvim_win_set_config(55, opts)

      assert.spy(scratch.set_win_config).called_with(scratch, match.deep_equal(opts))
      assert.is_nil(opts.use_minibuffer)
    end)

    it("passes unrelated nvim_win_set_config calls through", function()
      state.initialized = false
      state.default_nvim_win_set_config = spy.new(function() end)

      minibuffer.initialize()

      local opts = {
        width = 30,
      }

      vim_api.nvim_win_set_config(55, opts)

      assert.spy(state.default_nvim_win_set_config).called_with(55, opts)
    end)

    it("routes nvim_win_close to the active scratch session", function()
      state.initialized = false
      state.default_nvim_win_close = spy.new(function() end)

      local scratch = {
        type = function()
          return "scratch"
        end,
        get_win = function()
          return 55
        end,
        close = spy.new(function() end),
      }

      state.session = scratch

      minibuffer.initialize()

      vim_api.nvim_win_close(55, true)

      assert.spy(scratch.close).called_at_least(1)
      assert.spy(state.default_nvim_win_close).called_with(55, true)
    end)

    it("passes unrelated nvim_win_close calls through", function()
      state.initialized = false
      state.default_nvim_win_close = spy.new(function() end)

      minibuffer.initialize()

      vim_api.nvim_win_close(55, true)

      assert.spy(state.default_nvim_win_close).called_with(55, true)
    end)
  end)
end)
