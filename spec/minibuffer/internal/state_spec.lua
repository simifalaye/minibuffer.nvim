local helper = require("helper")
local state = require("minibuffer.internal.state")
local assert = helper.init()

describe("minibuffer.internal.state", function()
  before_each(function()
    state.session = nil
    state.prev_session = nil
    state.pending_render = false
    state.win_states = {}
  end)

  describe("cleanup", function()
    it("resets win_states so stale views are not restored later", function()
      state.win_states = { [1] = { height = 10, buf = 1, view = { lnum = 5 } } }

      state.cleanup()

      assert.same({}, state.win_states)
    end)

    it("clears the session and pending render", function()
      state.session = { resumable = function()
        return false
      end }
      state.pending_render = true

      state.cleanup()

      assert.is_nil(state.session)
      assert.is_false(state.pending_render)
    end)

    it("keeps a resumable session as the previous session", function()
      local session = { resumable = function()
        return true
      end }
      state.session = session

      state.cleanup()

      assert.equal(session, state.prev_session)
    end)
  end)
end)
