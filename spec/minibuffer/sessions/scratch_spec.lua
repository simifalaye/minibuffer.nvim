local config = require("minibuffer.config")
local helper = require("helper")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")
local assert, match, spy = helper.init()

describe("minibuffer.sessions.scratch", function()
  local ScratchSession

  local cmd_buf
  local cmd_win
  local scratch_buf
  local scratch_win

  local vim_api

  local states

  before_each(function()
    helper.init_stubs()

    package.loaded["minibuffer.sessions.scratch"] = nil
    ScratchSession = require("minibuffer.sessions.scratch")
    cmd_buf = 1
    cmd_win = 2
    scratch_buf = 3
    scratch_win = 4

    vim_api = vim.api

    states = {
      [10] = {
        height = 20,
        buf = 10,
        view = {},
      },
    }

    state.session = nil
    state.active_window = nil
    state.win_states = nil
    state.ns = 42

    helper.stub_method(util, "get_cmd_buf", function()
      return cmd_buf
    end)
    helper.stub_method(util, "get_cmd_win", function()
      return cmd_win
    end)
    helper.stub_method(util, "get_window_states", function()
      return states
    end)
    helper.stub_method(util, "wipe_cmd_buffer")
    helper.stub_method(util, "set_cmdheight")
    helper.stub_method(util, "restore_window_states")

    helper.stub_method(state, "cleanup")

    helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
      return win ~= nil and win ~= -1
    end)
    helper.stub_method(vim_api, "nvim_win_get_config", function(win)
      if win == cmd_win then
        return {
          zindex = 50,
        }
      end
      return {
        height = 5,
        border = "none",
      }
    end)
    helper.stub_method(vim_api, "nvim_win_close")
    helper.stub_method(vim_api, "nvim_set_current_win")
    helper.stub_method(vim_api, "nvim_create_augroup", function()
      return 100
    end)
    helper.stub_method(vim_api, "nvim_create_autocmd")
    helper.stub_method(vim_api, "nvim__redraw")

    helper.stub_method(vim, "schedule", function(callback)
      callback()
    end)

    helper.stub_method(state, "default_nvim_open_win", function()
      return scratch_win
    end)
    helper.stub_method(state, "default_nvim_win_set_config")

    vim.o.columns = 80
    vim.o.lines = 24
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  local function new_session(opts)
    opts = opts or {}
    opts.buf = opts.buf or scratch_buf
    opts.win_config = opts.win_config or {
      height = 5,
      border = "none",
    }
    if opts.enter == nil then
      opts.enter = false
    end
    return ScratchSession.new(opts)
  end

  describe(".new", function()
    it("creates a closed scratch session with defaults", function()
      local session = ScratchSession.new()

      assert.is_true(session._closed)
      assert.is_nil(session.buf)
      assert.is_nil(session.win_config)
      assert.is_nil(session.enter)
      assert.equal(-1, session._win)
    end)

    it("accepts all options", function()
      local win_config = {
        relative = "editor",
        width = 20,
        height = 10,
        border = "rounded",
      }

      local session = ScratchSession.new({
        buf = scratch_buf,
        win_config = win_config,
        enter = true,
      })

      assert.equal(scratch_buf, session.buf)
      assert.same(win_config, session.win_config)
      assert.is_true(session.enter)
      assert.is_true(session._closed)
      assert.equal(-1, session._win)
    end)
  end)

  describe(":resumable", function()
    it("is not resumable", function()
      assert.is_false(new_session():resumable())
    end)
  end)

  describe(":type", function()
    it("returns scratch", function()
      assert.equal("scratch", new_session():type())
    end)
  end)

  describe(":overridable", function()
    it("is overridable", function()
      assert.is_true(new_session():overridable())
    end)
  end)

  describe(":pre_start", function()
    it("does nothing when the command window is unavailable", function()
      util.get_cmd_win:revert()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      local session = new_session()

      session:pre_start()

      assert.is_true(session._closed)
      assert.is_nil(state.win_states)
      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
    end)

    it("opens the session and saves window state", function()
      local session = new_session()

      session:pre_start()

      assert.is_false(session._closed)
      assert.equal(states, state.win_states)
      assert.stub(util.wipe_cmd_buffer).called_at_least(1)
    end)

    it("does not create the scratch window during pre_start", function()
      local session = new_session()

      session:pre_start()

      assert.equal(-1, session._win)
      assert.stub(state.default_nvim_open_win).called_at_most(0)
    end)
  end)

  describe(":render", function()
    it("does nothing when closed", function()
      local session = new_session()

      session:render()

      assert.stub(util.get_cmd_win).called_at_most(0)
      assert.stub(state.default_nvim_open_win).called_at_most(0)
      assert.stub(vim_api.nvim__redraw).called_at_most(0)
    end)

    it("does nothing when the command window is unavailable", function()
      local session = new_session()
      session._closed = false

      util.get_cmd_win:revert()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      session:render()

      assert.equal(-1, session._win)
      assert.stub(state.default_nvim_open_win).called_at_most(0)
      assert.stub(vim_api.nvim__redraw).called_at_most(0)
    end)

    it("creates the scratch window when it does not exist", function()
      local session = new_session({
        buf = scratch_buf,
        enter = true,
        win_config = {
          height = 7,
          border = "none",
        },
      })
      session._closed = false

      session:render()

      assert.equal(scratch_win, session._win)

      assert.stub(state.default_nvim_open_win).called_with(scratch_buf, true, {
        height = 7,
        border = "none",
        anchor = "SW",
        relative = "editor",
        row = 24,
        col = 0,
        width = 80,
        win = cmd_win,
        zindex = 51,
      })
    end)

    it("uses the configured enter value when opening the window", function()
      local session = new_session({
        enter = false,
      })
      session._closed = false

      session:render()

      assert
        .stub(state.default_nvim_open_win)
        .called_with(scratch_buf, false, match.is_table())
    end)

    it("creates a WinClosed autocmd for the scratch window", function()
      local session = new_session()
      session._closed = false

      session:render()

      assert
        .stub(vim_api.nvim_create_augroup)
        .called_with("minibuffer-win-" .. tostring(scratch_win), { clear = true })

      assert.stub(vim_api.nvim_create_autocmd).called_with("WinClosed", match.is_table())

      local opts = vim_api.nvim_create_autocmd.calls[1].refs[2]
      assert.equal(100, opts.group)
      assert.equal(tostring(scratch_win), opts.pattern)
      assert.is_function(opts.callback)
    end)

    it("closes the session when the scratch window is closed", function()
      local session = new_session()
      session._closed = false

      session.close = spy.new(function()
        session._closed = true
      end)

      session:render()

      local opts = vim_api.nvim_create_autocmd.calls[1].refs[2]
      opts.callback()

      assert.spy(session.close).called_at_least(1)
    end)

    it("does not recreate an existing valid window", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      session:render()

      assert.stub(state.default_nvim_open_win).called_at_most(0)
      assert.stub(vim_api.nvim_create_autocmd).called_at_most(0)
    end)

    it("recreates the window when the existing window is invalid", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
        return win == cmd_win
      end)

      session:render()

      assert.equal(scratch_win, session._win)
      assert.stub(state.default_nvim_open_win).called_at_least(1)
    end)

    it("sets command height from the window height with no border", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_get_config", function(win)
        if win == cmd_win then
          return { zindex = 50 }
        end

        return {
          height = 5,
          border = "none",
        }
      end)

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 5)
    end)

    it("adds two rows for a non-none string border", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_get_config", function(win)
        if win == cmd_win then
          return { zindex = 50 }
        end

        return {
          height = 5,
          border = "rounded",
        }
      end)

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 7)
    end)

    it("adds a row for each non-empty top and bottom border", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_get_config", function(win)
        if win == cmd_win then
          return { zindex = 50 }
        end

        return {
          height = 5,
          border = {
            "topleft",
            "top",
            "topright",
            "right",
            "bottomright",
            "bottom",
            "bottomleft",
            "left",
          },
        }
      end)

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 7)
    end)

    it("does not add rows for empty top and bottom borders", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_get_config", function(win)
        if win == cmd_win then
          return { zindex = 50 }
        end

        return {
          height = 5,
          border = {
            "",
            "",
            "",
            "right",
            "",
            "",
            "",
            "left",
          },
        }
      end)

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize, 5)
    end)

    it("redraws after rendering", function()
      local session = new_session()
      session._closed = false

      session:render()

      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)
  end)

  describe(":post_start", function()
    it("does nothing", function()
      local session = new_session()

      assert.has_no_error(function()
        session:post_start()
      end)
    end)
  end)

  describe(":cancel", function()
    it("does nothing when already closed", function()
      local session = new_session()

      session.close = spy.new(function() end)

      session:cancel()

      assert.spy(session.close).called_at_most(0)
    end)

    it("closes an active session", function()
      local session = new_session()
      session._closed = false

      session.close = spy.new(function() end)

      session:cancel()

      assert.spy(session.close).called_at_least(1)
    end)
  end)

  describe(":close", function()
    it("does nothing when already closed", function()
      local session = new_session()

      session:close()

      assert.stub(vim_api.nvim_win_close).called_at_most(0)
      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
      assert.stub(util.restore_window_states).called_at_most(0)
      assert.stub(state.cleanup).called_at_most(0)
    end)

    it("marks the session closed", function()
      local session = new_session()
      session._closed = false

      session:close()

      assert.is_true(session._closed)
      assert.equal(-1, session._win)
    end)

    it("closes the scratch window", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      session:close()

      assert.stub(vim_api.nvim_win_close).called_with(scratch_win, true)
      assert.equal(-1, session._win)
    end)

    it("does not fail when the scratch window is invalid", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
        return win == cmd_win
      end)

      assert.has_no_error(function()
        session:close()
      end)

      assert.stub(vim_api.nvim_win_close).called_at_most(0)
      assert.equal(-1, session._win)
    end)

    it("does not restore state when the command window is unavailable", function()
      local session = new_session()
      session._closed = false

      util.get_cmd_win:revert()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      session:close()

      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
      assert.stub(util.set_cmdheight).called_at_most(0)
      assert.stub(util.restore_window_states).called_at_most(0)
      assert.stub(state.cleanup).called_at_most(0)
    end)

    it("wipes the command buffer and restores command height", function()
      local session = new_session()
      session._closed = false

      session:close()

      assert.stub(util.wipe_cmd_buffer).called_at_least(1)
      assert
        .stub(util.set_cmdheight)
        .called_with(state.win_states, config.dynamic_window_resize)
      assert.stub(util.restore_window_states).called_with(state.win_states)
    end)

    it("restores the previously active window", function()
      local session = new_session()
      session._closed = false
      state.active_window = 99

      session:close()

      assert.stub(vim_api.nvim_set_current_win).called_with(99)
    end)

    it("does not restore an invalid active window", function()
      local session = new_session()
      session._closed = false
      state.active_window = 99

      helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
        return win ~= 99
      end)

      session:close()

      assert.stub(vim_api.nvim_set_current_win).called_at_most(0)
    end)

    it("calls state.cleanup", function()
      local session = new_session()
      session._closed = false

      session:close()

      assert.stub(state.cleanup).called_at_least(1)
    end)

    it("calls the done callback", function()
      local session = new_session()
      session._closed = false

      local done = spy.new(function() end)

      session:close(done)

      assert.spy(done).called_at_least(1)
    end)

    it("does not fail when closing the window throws", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_close", function()
        error("boom")
      end)

      assert.has_no_error(function()
        session:close()
      end)

      assert.equal(-1, session._win)
      assert.stub(util.restore_window_states).called_with(state.win_states)
    end)
  end)

  describe(":set_win_config", function()
    it("returns false when the session is closed", function()
      local session = new_session()

      assert.is_false(session:set_win_config({
        height = 10,
      }))

      assert.stub(state.default_nvim_win_set_config).called_at_most(0)
    end)

    it("does nothing when the command window is unavailable", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      util.get_cmd_win:revert()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      assert.is_nil(session:set_win_config({
        height = 10,
      }))

      assert.stub(state.default_nvim_win_set_config).called_at_most(0)
    end)

    it("does nothing when the scratch window is invalid", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
        return win == cmd_win
      end)

      assert.is_nil(session:set_win_config({
        height = 10,
      }))

      assert.stub(state.default_nvim_win_set_config).called_at_most(0)
    end)

    it("updates the window configuration", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      session.render = spy.new(function() end)

      local cfg = {
        height = 12,
        border = "rounded",
      }

      session:set_win_config(cfg)

      assert.stub(state.default_nvim_win_set_config).called_with(scratch_win, {
        height = 12,
        border = "rounded",
        anchor = "SW",
        relative = "editor",
        row = 24,
        col = 0,
        width = 80,
        win = cmd_win,
        zindex = 51,
      })
    end)

    it("uses the command window zindex plus one", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      helper.stub_method(vim_api, "nvim_win_get_config", function(win)
        if win == cmd_win then
          return {
            zindex = 100,
          }
        end

        return {
          height = 5,
          border = "none",
        }
      end)

      session.render = spy.new(function() end)

      session:set_win_config({
        height = 8,
      })

      local call = state.default_nvim_win_set_config.calls[1].refs
      assert.equal(101, call[2].zindex)
    end)

    it("renders after updating the configuration", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      session.render = spy.new(function() end)

      session:set_win_config({
        height = 10,
      })

      assert.spy(session.render).called_at_least(1)
    end)

    it("preserves arbitrary supplied window configuration", function()
      local session = new_session()
      session._closed = false
      session._win = scratch_win

      session.render = spy.new(function() end)

      session:set_win_config({
        height = 10,
        width = 30,
        border = "double",
        style = "minimal",
        focusable = false,
      })

      local cfg = state.default_nvim_win_set_config.calls[1].refs[2]

      assert.equal(10, cfg.height)
      assert.equal(vim.o.columns, cfg.width)
      assert.equal("double", cfg.border)
      assert.equal("minimal", cfg.style)
      assert.is_false(cfg.focusable)
      assert.equal("SW", cfg.anchor)
      assert.equal("editor", cfg.relative)
      assert.equal(24, cfg.row)
      assert.equal(0, cfg.col)
      assert.equal(cmd_win, cfg.win)
      assert.equal(51, cfg.zindex)
    end)
  end)

  describe(":get_win", function()
    it("returns the current window id", function()
      local session = new_session()

      assert.equal(-1, session:get_win())

      session._win = scratch_win

      assert.equal(scratch_win, session:get_win())
    end)
  end)
end)
