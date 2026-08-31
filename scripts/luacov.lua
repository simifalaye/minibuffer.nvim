--- Run Busted unit tests with LuaCov enabled.
---
--- This generates `luacov.stats.out`, which can then be processed by
--- `luacov --reporter multiple`.

local current_directory =
  vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h")

local stats_file = vim.fs.joinpath(current_directory, "luacov.stats.out")

-- Remove coverage data from the previous run.
if vim.fn.filereadable(stats_file) == 1 then
  os.remove(stats_file)
end

-- LuaJIT's JIT compiler can interfere with coverage.
if jit then
  jit.off()
end

-- Initialize LuaCov and install its debug hook.
local luacov = require("luacov")
luacov.init()

-- Load the project's test configuration.
dofile("spec/minimal_init.lua")

-- Busted arguments.
_G.arg = {
  "--ignore-lua",
  [0] = "spec/minimal_init.lua",
}

-- Run Busted in-process.
require("busted.runner")({
  standalone = false,
})

-- Explicitly write the collected statistics.
luacov.save_stats()
luacov.shutdown()
