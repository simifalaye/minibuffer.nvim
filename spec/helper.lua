local stub = require("luassert.stub")
local stubs = setmetatable({}, { __mode = "k" })

local initialized = false

local M = {}

function M.init()
  local assert = require("luassert")
  local match = require("luassert.match")
  local spy = require("luassert.spy")

  if initialized then
    return assert, match, spy
  end
  initialized = true

  ---@cast match +{ deep_equal: fun(expected: table): fun(actual: table): boolean }
  ---@cast match +{ satisfies: fun(f: function): fun(actual: any): boolean }

  assert:register("matcher", "deep_equal", function(_, arguments)
    local expected = arguments[1]
    return function(actual)
      return vim.deep_equal(actual, expected)
    end
  end, "assertion.deep_equal.positive", "assertion.deep_equal.negative")

  assert:register("matcher", "satisfies", function(_, arguments)
    local f = arguments[1]
    return function(actual)
      return f(actual)
    end
  end, "assertion.satisfies.positive", "assertion.satisfies.negative")

  return assert, match, spy
end

function M.init_stubs()
  stubs = setmetatable({}, { __mode = "k" })
end

function M.stub_method(object, method, ...)
  stubs[object] = stubs[object] or {}

  local existing = stubs[object][method]
  if existing then
    existing:revert()
    stubs[object][method] = nil
  end

  local new_stub = stub(object, method, ...)
  stubs[object][method] = new_stub

  return new_stub
end

function M.revert_stubs()
  for _, methods in pairs(stubs) do
    for method, s in pairs(methods) do
      s:revert()
      methods[method] = nil
    end
  end
end

return M
