local config = require("minibuffer.config")
local helper = require("helper")
local state = require("minibuffer.internal.state")
local util = require("minibuffer.internal.util")
local assert, match, spy = helper.init()

describe("minibuffer.sessions.input", function()
  local InputSession
  local cmd_buf
  local cmd_win
  local entry_buf
  local entry_win
  local display_buf
  local display_win
  local nvim_create_buf_called

  local vim_api
  local vim_fn
  local vim_keymap

  local states

  local vim_notify_stub
  local vim_cmd_stub

  before_each(function()
    helper.init_stubs()

    package.loaded["minibuffer.sessions.input"] = nil
    InputSession = require("minibuffer.sessions.input")
    cmd_buf = 1
    cmd_win = 2
    entry_buf = 3
    entry_win = 4
    display_buf = 5
    display_win = 6
    nvim_create_buf_called = false

    vim_api = vim.api
    vim_fn = vim.fn
    vim_keymap = vim.keymap

    states = {
      [10] = {
        height = 20,
        buf = 10,
        view = {},
      },
    }

    state.session = nil
    state.active_window = nil
    state.win_states = states
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
    helper.stub_method(util, "restore_window_states")
    helper.stub_method(util, "write_highlighted_lines")
    helper.stub_method(util, "set_cmdheight")
    helper.stub_method(util, "set_win_height")
    helper.stub_method(util, "focus_win", function(win)
      return win
    end)
    helper.stub_method(util, "create_condition_keyset", function(_, opts)
      return function(mode, lhs, rhs)
        vim_keymap.set(mode, lhs, rhs, opts)
      end
    end)

    helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
      return win ~= nil
    end)
    helper.stub_method(vim_api, "nvim_buf_is_valid", function(buf)
      return buf ~= nil
    end)
    helper.stub_method(vim_api, "nvim_create_buf", function(_, _)
      if not nvim_create_buf_called then
        nvim_create_buf_called = true
        return display_buf
      end
      return entry_buf
    end)
    helper.stub_method(vim_api, "nvim_open_win", function(buf)
      if buf == display_buf then
        return display_win
      end
      return entry_win
    end)
    helper.stub_method(vim_api, "nvim_win_get_config", function()
      return {
        zindex = 50,
      }
    end)
    helper.stub_method(vim_api, "nvim_win_get_height", function()
      return 5
    end)
    helper.stub_method(vim_api, "nvim_win_set_config")
    helper.stub_method(vim_api, "nvim_win_close")
    helper.stub_method(vim_api, "nvim_buf_delete")
    helper.stub_method(vim_api, "nvim_win_call", function(_, fn)
      fn()
    end)
    helper.stub_method(vim_api, "nvim_set_option_value")
    helper.stub_method(vim_api, "nvim_buf_set_lines")
    helper.stub_method(vim_api, "nvim_win_set_cursor")
    helper.stub_method(vim_api, "nvim_buf_set_extmark")
    helper.stub_method(vim_api, "nvim__redraw")
    helper.stub_method(vim_api, "nvim_set_current_win")
    helper.stub_method(vim_api, "nvim_create_autocmd")
    helper.stub_method(vim_api, "nvim_buf_attach")
    helper.stub_method(vim_api, "nvim_feedkeys")

    helper.stub_method(vim_keymap, "set")

    helper.stub_method(vim_fn, "prompt_setprompt")
    helper.stub_method(vim_fn, "prompt_setcallback")
    helper.stub_method(vim_fn, "prompt_getinput", function()
      return ""
    end)
    helper.stub_method(vim_fn, "mode", function()
      return "n"
    end)

    helper.stub_method(vim, "schedule", function(callback)
      callback()
    end)

    vim_notify_stub = helper.stub_method(vim, "notify")
    vim_cmd_stub = helper.stub_method(vim, "cmd")

    vim.o.columns = 80
    vim.o.lines = 24
    vim.bo = vim.bo or {}
    vim.wo = vim.wo or {}
  end)

  after_each(function()
    helper.revert_stubs()
  end)

  local function new_session(opts)
    opts = opts or {}
    opts.fetch_fn = opts.fetch_fn or function(_, cb)
      cb({})
    end
    opts.format_fn = opts.format_fn
      or function(item)
        return { { tostring(item), "Normal" } }
      end
    return InputSession.new(opts)
  end

  describe(".new", function()
    it("creates a closed session with defaults", function()
      local session = new_session()

      assert.is_true(session._closed)
      assert.equal("Enter: ", session.prompt)
      assert.equal(15, session.max_height)
      assert.is_false(session.dynamic_height)
      assert.same({}, session._items)
      assert.equal("", session._input)
      assert.equal(0, session._current_index)
      assert.equal(0, session._scroll_offset)
      assert.is_false(session._loading)
      assert.equal(0, session._fetch_generation)
      assert.is_nil(session._timer)
    end)

    it("accepts all options", function()
      local fetch_fn = function() end
      local format_fn = function() end
      local footer_fn = function() end
      local on_start = function() end
      local on_accept = function() end
      local on_submit = function() end
      local on_cancel = function() end
      local on_close = function() end
      local on_change = function() end

      local session = InputSession.new({
        resumable = true,
        prompt = "Search: ",
        initial_text = "hello",
        max_height = 8,
        dynamic_height = true,
        fetch_fn = fetch_fn,
        format_fn = format_fn,
        footer_fn = footer_fn,
        on_start = on_start,
        on_accept = on_accept,
        on_submit = on_submit,
        on_cancel = on_cancel,
        on_close = on_close,
        on_change = on_change,
      })

      assert.equal("Search: ", session.prompt)
      assert.equal("hello", session._input)
      assert.equal(8, session.max_height)
      assert.is_true(session.dynamic_height)
      assert.equal(fetch_fn, session.fetch_fn)
      assert.equal(format_fn, session.format_fn)
      assert.equal(footer_fn, session.footer_fn)
      assert.equal(on_start, session.on_start)
      assert.equal(on_accept, session.on_accept)
      assert.equal(on_submit, session.on_submit)
      assert.equal(on_cancel, session.on_cancel)
      assert.equal(on_close, session.on_close)
      assert.equal(on_change, session.on_change)
      assert.is_true(session:resumable())
    end)

    it("is not resumable unless explicitly enabled", function()
      assert.is_false(new_session():resumable())
      assert.is_false(new_session({ resumable = false }):resumable())
    end)

    it("requires a fetch function", function()
      assert.has_error(function()
        InputSession.new({
          format_fn = function() end,
        })
      end)
    end)

    it("requires a format function", function()
      assert.has_error(function()
        InputSession.new({
          fetch_fn = function() end,
        })
      end)
    end)
  end)

  describe(":type", function()
    it("returns input", function()
      assert.equal("input", new_session():type())
    end)
  end)

  describe(":overridable", function()
    it("is overridable", function()
      assert.is_true(new_session():overridable())
    end)
  end)

  describe(":get_ctx", function()
    it("returns the current context", function()
      local session = new_session({
        initial_text = "abc",
      })

      session._items = { "one", "two" }
      session._current_index = 2
      session._loading = true

      assert.same({
        items = { "one", "two" },
        input = "abc",
        current_index = 2,
        loading = true,
      }, session:get_ctx())
    end)
  end)

  describe(":pre_start", function()
    it("does nothing when the command window is unavailable", function()
      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      local session = new_session()
      session:pre_start()

      assert.is_true(session._closed)
      assert.is_nil(session._display.buf)
      assert.is_nil(session._entry.buf)
      assert.stub(util.wipe_cmd_buffer).called_at_most(0)
    end)

    it("wipes the command buffer and opens the session", function()
      local session = new_session()

      session:pre_start()

      assert.is_false(session._closed)
      assert.stub(util.wipe_cmd_buffer).called_at_least(1)
      assert.same(states, state.win_states)
    end)

    it("creates the display buffer and window", function()
      local session = new_session({
        max_height = 10,
      })

      session._items = { "one", "two", "three" }
      session:pre_start()

      assert.equal(display_buf, session._display.buf)
      assert.equal(display_win, session._display.win)

      assert.stub(vim_api.nvim_open_win).called_with(display_buf, false, match.is_table())
    end)

    it("limits the initial display height to max_height", function()
      local session = new_session({
        max_height = 2,
      })

      session._items = { "one", "two", "three", "four" }
      session:pre_start()

      local opts = vim_api.nvim_open_win.calls[1].refs[3]
      assert.equal(2, opts.height)
    end)

    it("uses at least one row for an empty display", function()
      local session = new_session()

      session:pre_start()

      local opts = vim_api.nvim_open_win.calls[1].refs[3]
      assert.equal(1, opts.height)
    end)

    it("sets up the entry prompt", function()
      local session = new_session({
        prompt = "Find: ",
      })

      session:pre_start()

      assert.equal(entry_buf, session._entry.buf)
      assert.stub(vim_fn.prompt_setprompt).called_with(entry_buf, "Find: ")
      assert.stub(vim_fn.prompt_setcallback).called_with(entry_buf, match.is_function())
    end)

    it("creates the entry window below the display window", function()
      local session = new_session()

      session._items = { "one", "two" }
      session:pre_start()

      local opts = vim_api.nvim_open_win.calls[2].refs[3]

      assert.equal(3, opts.height)
      assert.equal(51, opts.zindex)
      assert.equal("none", opts.border)
    end)

    it("errors when the display buffer cannot be created", function()
      helper.stub_method(vim_api, "nvim_create_buf", function()
        return 0
      end)

      assert.has_error(function()
        new_session():pre_start()
      end, "Failed to create display minibuffer")
    end)
  end)

  describe(":render", function()
    local session

    before_each(function()
      session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }
      state.win_states = states
    end)

    it("does nothing when closed", function()
      session._closed = true

      session:render()

      assert.stub(vim_api.nvim_win_get_height).called_at_most(0)
      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("does nothing when the entry window is invalid", function()
      helper.stub_method(vim_api, "nvim_win_is_valid", function(win)
        return win ~= entry_win
      end)

      session:render()

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("does nothing when the display buffer is invalid", function()
      helper.stub_method(vim_api, "nvim_buf_is_valid", function(buf)
        return buf ~= display_buf
      end)

      session:render()

      assert.stub(util.write_highlighted_lines).called_at_most(0)
    end)

    it("renders formatted items", function()
      session._items = { "one", "two" }
      session._current_index = 1

      local format_fn = spy.new(function(item)
        return { { item, "String" } }
      end)
      session.format_fn = format_fn

      session:render()

      assert.spy(format_fn).called_with("one")
      assert.spy(format_fn).called_with("two")

      assert.stub(util.write_highlighted_lines).called_with(display_buf, state.ns, {
        { { "one", "String" } },
        { { "two", "String" } },
      })
    end)

    it("uses loading state when calculating the height", function()
      session._items = { "one", "two" }
      session._loading = true

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 0
      end)

      session:render()

      assert.stub(util.set_win_height).called_with(display_win, 3)
      assert.stub(util.set_win_height).called_with(entry_win, 5)
    end)

    it("renders a loading row", function()
      session._items = { "one" }
      session._loading = true
      session.format_fn = function(item)
        return { { item, "Normal" } }
      end

      session:render()

      local call = util.write_highlighted_lines.calls[1].refs[3]

      assert.same({
        { { "one", "Normal" } },
        { { text = " … loading …", hl = "MinibufferLoading" } },
      }, call)
    end)

    it("does not shrink when dynamic height is disabled", function()
      session.dynamic_height = false
      session._items = { "one" }

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 5
      end)

      session:render()

      assert.stub(util.set_win_height).called_with(display_win, 5)
      assert.stub(util.set_win_height).called_with(entry_win, 7)
    end)

    it("shrinks when dynamic height is enabled", function()
      session.dynamic_height = true
      session._items = { "one" }

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 5
      end)

      session:render()

      assert.stub(util.set_win_height).called_with(display_win, 1)
      assert.stub(util.set_win_height).called_with(entry_win, 3)
    end)

    it("respects max_height", function()
      session.max_height = 2
      session._items = { "one", "two", "three", "four" }

      session:render()

      assert.stub(util.set_win_height).called_with(display_win, 2)
      assert.stub(util.set_win_height).called_with(entry_win, 4)
    end)

    it("adds the command height for the entry window", function()
      session._items = { "one", "two", "three" }

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 0
      end)

      session:render()

      assert
        .stub(util.set_cmdheight)
        .called_with(match.deep_equal(state.win_states), config.dynamic_window_resize, 5)
    end)

    it("marks the selected item", function()
      session._items = { "one", "two" }
      session._current_index = 2

      session:render()

      assert.stub(vim_api.nvim_buf_set_extmark).called_with(display_buf, state.ns, 1, 0, {
        line_hl_group = "MinibufferSelection",
      })
    end)

    it("does not mark an item when there is no selection", function()
      session._items = { "one", "two" }
      session._current_index = 0

      session:render()

      assert.stub(vim_api.nvim_buf_set_extmark).called_at_most(0)
    end)

    it("calls on_change with the current context", function()
      session._items = { "one", "two" }
      session._input = "foo"
      session._current_index = 2

      local on_change = spy.new(function() end)
      session.on_change = on_change

      session:render()

      assert.spy(on_change).called_with("foo", "two")
    end)

    it("redraws after rendering", function()
      session:render()

      assert.stub(vim_api.nvim__redraw).called_with({
        flush = true,
        cursor = true,
      })
    end)

    it("scrolls down when the selected item is below the viewport", function()
      session._items = { "1", "2", "3", "4", "5" }
      session._current_index = 5
      session.max_height = 3

      helper.stub_method(vim_api, "nvim_win_get_height", function()
        return 3
      end)

      session:render()

      assert.equal(2, session._scroll_offset)
    end)

    it("scrolls up when the selected item is above the viewport", function()
      session._items = { "1", "2", "3", "4", "5" }
      session._current_index = 1
      session._scroll_offset = 3
      session.max_height = 3

      session:render()

      assert.equal(0, session._scroll_offset)
    end)

    it("resets scroll when all items fit", function()
      session._items = { "1", "2" }
      session._scroll_offset = 5

      session:render()

      assert.equal(0, session._scroll_offset)
    end)
  end)

  describe(":post_start", function()
    it("does nothing when closed", function()
      local session = new_session()

      session:post_start()

      assert.spy(vim_keymap.set).called_at_most(0)
    end)

    it("does nothing when the entry window is invalid", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = nil }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.spy(vim_keymap.set).called_at_most(0)
    end)

    it("creates all default mappings", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.spy(vim_keymap.set).called_at_least(11)

      local lhs = {}
      for _, call in ipairs(vim_keymap.set.calls) do
        lhs[call.refs[2]] = true
      end

      for _, key in ipairs({
        "<Esc>",
        "<C-c>",
        "<CR>",
        "<Up>",
        "<Down>",
        "<C-p>",
        "<C-n>",
        "<S-Tab>",
        "<Tab>",
        "<C-y>",
        "<C-w>",
      }) do
        assert.is_true(lhs[key])
      end
    end)

    it("uses the expected mapping options", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      local opts = vim_keymap.set.calls[1].refs[4]

      assert.same({
        buf = entry_buf,
        nowait = true,
        silent = true,
        noremap = true,
      }, opts)
    end)

    it("calls on_start", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      local received_session
      local received_keyset
      local on_start = spy.new(function(s, keyset)
        received_session = s
        received_keyset = keyset
      end)
      session.on_start = on_start

      session:post_start()

      assert.equal(session, received_session)
      assert.is_function(received_keyset)
    end)

    it("focuses the entry window", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.equal(entry_win, state.active_window)
      assert.stub(util.focus_win).called_with(entry_win)
    end)

    it("starts insert mode", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.stub(vim_api.nvim_win_call).called_at_least(1)
      assert.stub(vim_cmd_stub).called_with("startinsert")
    end)

    it("feeds initial input", function()
      local session = new_session({
        initial_text = "hello",
      })
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.stub(vim_api.nvim_feedkeys).called_with("hello", "t", false)
    end)

    it("does not feed input when initial text is empty", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.stub(vim_api.nvim_feedkeys).called_at_most(0)
    end)

    it("attaches a buffer listener", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:post_start()

      assert.stub(vim_api.nvim_buf_attach).called_with(entry_buf, false, match.is_table())
    end)

    it("refreshes suggestions when there are no items", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session.refresh_suggestions = spy.new(function() end)

      session:post_start()

      assert.spy(session.refresh_suggestions).called_at_least(1)
    end)
  end)

  describe(":refresh_suggestions", function()
    it("does nothing when closed", function()
      local session = new_session()

      session:refresh_suggestions()

      assert.is_false(session._loading)
      assert.equal(0, session._fetch_generation)
    end)

    it("does nothing when the command window is unavailable", function()
      local session = new_session()
      session._closed = false

      helper.stub_method(util, "get_cmd_win", function()
        return nil
      end)

      session:refresh_suggestions()

      assert.is_false(session._loading)
      assert.equal(0, session._fetch_generation)
    end)

    it("marks the session as loading and calls fetch_fn", function()
      local session = new_session()
      session._closed = false
      session._input = "abc"

      local fetch = spy.new(function(_, cb)
        cb({ "one", "two" })
      end)
      session.fetch_fn = fetch
      session.render = spy.new(function() end)

      session:refresh_suggestions()

      assert.spy(fetch).called_with("abc", match.is_function())
      assert.is_false(session._loading)
      assert.same({ "one", "two" }, session._items)
      assert.equal(1, session._current_index)
      assert.spy(session.render).called_at_least(1)
    end)

    it("increments the fetch generation", function()
      local session = new_session()
      session._closed = false

      session.fetch_fn = function() end

      session:refresh_suggestions()
      assert.equal(1, session._fetch_generation)

      session:refresh_suggestions()
      assert.equal(2, session._fetch_generation)
    end)

    it("resets selection when suggestions are empty", function()
      local session = new_session()
      session._closed = false
      session._current_index = 3
      session._scroll_offset = 4

      session.fetch_fn = function(_, cb)
        cb({})
      end

      session:refresh_suggestions()

      assert.same({}, session._items)
      assert.equal(0, session._current_index)
      assert.equal(0, session._scroll_offset)
      assert.is_false(session._loading)
    end)

    it("selects the first item when suggestions are returned", function()
      local session = new_session()
      session._closed = false
      session._current_index = 0
      session._scroll_offset = 5

      session.fetch_fn = function(_, cb)
        cb({ "one", "two" })
      end

      session:refresh_suggestions()

      assert.same({ "one", "two" }, session._items)
      assert.equal(1, session._current_index)
      assert.equal(0, session._scroll_offset)
    end)

    it("handles fetch errors", function()
      local session = new_session()
      session._closed = false
      session.render = spy.new(function() end)

      session.fetch_fn = function(_, cb)
        cb(nil, "failed")
      end

      session:refresh_suggestions()

      assert.is_false(session._loading)
      assert.spy(session.render).called_at_least(1)
    end)

    it("notifies when fetch_fn itself throws", function()
      local session = new_session()
      session._closed = false

      session.fetch_fn = function()
        error("boom")
      end

      session:refresh_suggestions()

      assert
        .stub(vim_notify_stub)
        .called_with(match.matches("Failed to fetch data", 0, true))
    end)

    it("uses ERROR when the fetch error is not a string", function()
      local session = new_session()
      session._closed = false

      session.fetch_fn = function()
        error({ reason = "boom" })
      end

      session:refresh_suggestions()

      assert
        .stub(vim_notify_stub)
        .called_with(match.matches("Failed to fetch data", 0, true))
    end)

    it("discards a stale fetch result", function()
      local session = new_session()
      session._closed = false

      local callbacks = {}

      session.fetch_fn = function(_, cb)
        callbacks[#callbacks + 1] = cb
      end

      session:refresh_suggestions()
      session:refresh_suggestions()

      callbacks[1]({ "stale" })

      assert.same({}, session._items)
      assert.equal(0, session._current_index)

      callbacks[2]({ "current" })

      assert.same({ "current" }, session._items)
      assert.equal(1, session._current_index)
    end)

    it("discards results after the session closes", function()
      local session = new_session()
      session._closed = false

      local callback

      session.fetch_fn = function(_, cb)
        callback = cb
      end

      session:refresh_suggestions()
      session._closed = true

      callback({ "ignored" })

      assert.same({}, session._items)
    end)
  end)

  describe(":set_input", function()
    local session

    before_each(function()
      session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }
    end)

    it("does nothing when closed", function()
      session._closed = true

      session:set_input("hello")

      assert.equal("", session._input)
      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("does nothing when the entry window is invalid", function()
      session._entry.win = nil

      session:set_input("hello")

      assert.equal("", session._input)
      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("sets the prompt text and cursor", function()
      session.prompt = "Find: "
      session.refresh_suggestions = spy.new(function() end)

      session:set_input("hello")

      assert
        .stub(vim_api.nvim_buf_set_lines)
        .called_with(entry_buf, 0, 1, false, { "Find: hello" })

      assert.stub(vim_api.nvim_win_set_cursor).called_with(0, { 1, 11 })

      assert.equal("hello", session._input)
      assert.spy(session.refresh_suggestions).called_at_least(1)
    end)
  end)

  describe(":accept", function()
    local session

    before_each(function()
      session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }
    end)

    it("does nothing when closed", function()
      session._closed = true
      session._items = { "one" }
      session._current_index = 1

      session:accept()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("does nothing when there is no selection", function()
      session._items = { "one" }
      session._current_index = 0

      session:accept()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("does nothing when there are no items", function()
      session._current_index = 0
      session._items = {}

      session:accept()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("does nothing while loading", function()
      session._items = { "one" }
      session._current_index = 1
      session._loading = true

      session:accept()

      assert.stub(vim_api.nvim_buf_set_lines).called_at_most(0)
    end)

    it("appends the selected item by default", function()
      session._input = "hel"
      session._items = { "lo", "world" }
      session._current_index = 1

      local received_session
      session.set_input = spy.new(function(s)
        received_session = s
      end)

      session:accept()

      assert.spy(session.set_input).called_with(received_session, "hello")
    end)

    it("uses on_accept to transform the input", function()
      session._input = "hello"
      session._items = { " world" }
      session._current_index = 1

      local on_accept = spy.new(function(ctx)
        assert.equal("hello", ctx.input)
        assert.equal(" world", ctx.items[1])
        assert.equal(1, ctx.current_index)
        return "hello world"
      end)

      session.on_accept = on_accept

      local received_session
      session.set_input = spy.new(function(s)
        received_session = s
      end)

      session:accept()

      assert.spy(on_accept).called_at_least(1)
      assert.spy(session.set_input).called_with(received_session, "hello world")
    end)

    it("does not change the input when on_accept errors", function()
      session._items = { "one" }
      session._current_index = 1
      session.on_accept = function()
        error("boom")
      end
      session.set_input = spy.new(function() end)

      session:accept()

      assert.spy(session.set_input).called_at_most(0)
    end)
  end)

  describe(":move", function()
    local session

    before_each(function()
      session = new_session()
      session._closed = false
      session._items = { "one", "two", "three" }
      session._current_index = 1
      session.render = spy.new(function() end)
    end)

    it("does nothing when closed", function()
      session._closed = true

      session:move(1)

      assert.equal(1, session._current_index)
      assert.spy(session.render).called_at_most(0)
    end)

    it("does nothing when there are no items", function()
      session._items = {}

      session:move(1)

      assert.equal(1, session._current_index)
      assert.spy(session.render).called_at_most(0)
    end)

    it("moves forward", function()
      session:move(1)

      assert.equal(2, session._current_index)
      assert.spy(session.render).called_at_least(1)
    end)

    it("moves backward", function()
      session._current_index = 2

      session:move(-1)

      assert.equal(1, session._current_index)
      assert.spy(session.render).called_at_least(1)
    end)

    it("wraps from the last item to the first", function()
      session._current_index = 3

      session:move(1)

      assert.equal(1, session._current_index)
    end)

    it("wraps from the first item to the last", function()
      session:move(-1)

      assert.equal(3, session._current_index)
    end)

    it("supports arbitrary deltas", function()
      session:move(2)

      assert.equal(3, session._current_index)
    end)
  end)

  describe(":submit", function()
    it("does nothing when closed", function()
      local session = new_session()

      session:submit()

      assert.stub(util.restore_window_states).called_at_most(0)
    end)

    it("closes the session", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session:submit()

      assert.is_true(session._closed)
    end)

    it("calls on_submit with the final context", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }
      session._input = "hello"
      session._items = { "one" }
      session._current_index = 1

      local on_submit = spy.new(function() end)
      session.on_submit = on_submit

      session:submit()

      assert.spy(on_submit).called_with({
        items = { "one" },
        input = "hello",
        current_index = 1,
        loading = false,
      })
    end)

    it("does not fail when on_submit throws", function()
      local session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }

      session.on_submit = function()
        error("boom")
      end

      assert.has_no_error(function()
        session:submit()
      end)
    end)
  end)

  describe(":cancel", function()
    it("does nothing when closed", function()
      local session = new_session()

      session.close = spy.new(function() end)
      session:cancel()

      assert.spy(session.close).called_at_most(0)
    end)

    it("closes the session", function()
      local session = new_session()
      session._closed = false
      session.close = spy.new(function(_, done)
        assert.is_function(done)
      end)

      session:cancel()

      assert.spy(session.close).called_at_least(1)
    end)

    it("calls on_cancel after closing", function()
      local session = new_session()
      session._closed = false

      local on_cancel = spy.new(function() end)
      session.on_cancel = on_cancel

      session.close = function(_, done)
        done()
      end

      session:cancel()

      assert.spy(on_cancel).called_at_least(1)
    end)
  end)

  describe(":close", function()
    local session

    before_each(function()
      session = new_session()
      session._closed = false
      session._entry = { buf = entry_buf, win = entry_win }
      session._display = { buf = display_buf, win = display_win }
      state.active_window = 99
      state.win_states = states
    end)

    it("does nothing when already closed", function()
      session._closed = true

      session:close()

      assert.stub(util.set_cmdheight).called_at_most(0)
      assert.stub(util.restore_window_states).called_at_most(0)
    end)

    it("marks the session closed", function()
      session:close()

      assert.is_true(session._closed)
    end)

    it("invalidates outstanding fetch requests", function()
      session._fetch_generation = 4

      session:close()

      assert.equal(5, session._fetch_generation)
    end)

    it("restores command height and window state", function()
      session:close()

      assert.stub(util.set_cmdheight).called_with(states, config.dynamic_window_resize)
      assert.stub(util.restore_window_states).called_with(states)
    end)

    it("closes and deletes the display windows and buffers", function()
      session:close()

      assert.stub(vim_api.nvim_win_close).called_with(display_win, true)
      assert.stub(vim_api.nvim_buf_delete).called_with(display_buf, { force = true })
      assert.stub(vim_api.nvim_win_close).called_with(entry_win, true)
      assert.stub(vim_api.nvim_buf_delete).called_with(entry_buf, { force = true })

      assert.is_nil(session._display.win)
      assert.is_nil(session._display.buf)
      assert.is_nil(session._entry.win)
      assert.is_nil(session._entry.buf)
    end)

    it("restores the previously active window", function()
      session:close()

      assert.stub(vim_api.nvim_set_current_win).called_with(99)
    end)

    it("calls state.cleanup", function()
      state.cleanup = spy.new(function() end)

      session:close()

      assert.spy(state.cleanup).called_at_least(1)
    end)

    it("calls on_close", function()
      local on_close = spy.new(function() end)
      session.on_close = on_close

      session:close()

      assert.spy(on_close).called_at_least(1)
    end)

    it("calls the done callback", function()
      local done = spy.new(function() end)

      session:close(done)

      assert.spy(done).called_at_least(1)
    end)

    it("waits for InsertLeave while in insert mode", function()
      helper.stub_method(vim_fn, "mode", function()
        return "i"
      end)

      session:close()

      assert.stub(vim_api.nvim_create_autocmd).called_with(
        "InsertLeave",
        match.satisfies(function(arg)
          return arg.once and type(arg.callback) == "function"
        end)
      )
      assert.stub(vim_cmd_stub).called_with("stopinsert")
      assert.stub(util.restore_window_states).called_at_most(0)
    end)

    it("performs cleanup from the InsertLeave callback", function()
      helper.stub_method(vim_fn, "mode", function()
        return "i"
      end)

      session:close()

      local callback = vim_api.nvim_create_autocmd.calls[1].refs[2].callback
      callback()

      assert.stub(util.restore_window_states).called_with(states)
      assert.is_nil(session._display.win)
      assert.is_nil(session._entry.win)
    end)

    it("only performs cleanup once", function()
      state.cleanup = spy.new(function() end)

      session:close()
      session:close()

      assert.stub(util.restore_window_states).called_at_most(1)
      assert.stub(state.cleanup).called_at_most(1)
    end)
  end)
end)
