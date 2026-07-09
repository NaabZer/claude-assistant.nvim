-- Shared headless-nvim test harness helpers, required by tests/*_spec.lua.

local M = {}

-- Use io.stdout directly (with an explicit flush) rather than print(): under
-- `nvim -l`, the process can exit before print()'s output is flushed, dropping
-- the trailing newline (and, in the worst case, the line itself).
function M.fail(msg)
  io.stdout:write("FAIL: " .. msg .. "\n")
  io.stdout:flush()
  os.exit(1, true)
end

function M.pass(msg)
  io.stdout:write("PASS: " .. msg .. "\n")
  io.stdout:flush()
end

return M
