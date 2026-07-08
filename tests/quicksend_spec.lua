-- Headless-nvim harness for lua/claude-assistant/send.lua.
-- Run with: nvim -l tests/quicksend_spec.lua
--
-- Keep this minimal: it currently only covers the `fire` helper's on_result
-- contract. Later commits add more cases as new senders land.

-- Use io.stdout directly (with an explicit flush) rather than print(): under
-- `nvim -l`, the process can exit before print()'s output is flushed, dropping
-- the trailing newline (and, in the worst case, the line itself).
local function fail(msg)
  io.stdout:write("FAIL: " .. msg .. "\n")
  io.stdout:flush()
  os.exit(1, true)
end

local function pass(msg)
  io.stdout:write("PASS: " .. msg .. "\n")
  io.stdout:flush()
end

-- Resolve the plugin root from this script's own path so it works regardless
-- of the caller's cwd, then make `require("claude-assistant.send")` resolvable.
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local root = script_dir .. "../"
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

-- Stub claudecode.terminal BEFORE requiring send.lua so the harness controls
-- get_active_terminal_bufnr/ensure_visible/send_to_terminal instead of needing
-- a real Claude Code pane.
local calls = {
  ensure_visible = 0,
  send_to_terminal = {},
}

package.preload["claudecode.terminal"] = function()
  return {
    -- Non-nil bufnr means existed == true, which keeps fire() on the immediate
    -- path (no vim.defer_fn), so the assertion below doesn't need to pump the
    -- event loop.
    get_active_terminal_bufnr = function()
      return 1
    end,
    ensure_visible = function()
      calls.ensure_visible = calls.ensure_visible + 1
    end,
    send_to_terminal = function(payload, send_opts)
      table.insert(calls.send_to_terminal, { payload = payload, send_opts = send_opts })
      return true
    end,
  }
end

local send = require("claude-assistant.send")

if type(send._fire) ~= "function" then
  fail("send.lua does not expose M._fire")
end

local got_callback = false
local result_ok, result_existed

send._fire("hello", { submit = true, focus = false }, function(ok, existed)
  got_callback = true
  result_ok = ok
  result_existed = existed
end)

if not got_callback then
  fail("fire() did not invoke on_result")
end
if result_ok ~= true then
  fail("on_result ok = " .. tostring(result_ok) .. ", expected true")
end
if result_existed ~= true then
  fail("on_result existed = " .. tostring(result_existed) .. ", expected true")
end
if calls.ensure_visible ~= 1 then
  fail("ensure_visible called " .. calls.ensure_visible .. " times, expected 1")
end
if #calls.send_to_terminal ~= 1 then
  fail("send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 1")
end

pass("fire() invokes on_result(ok, existed) on the existed==true (immediate) path")
os.exit(0, true)
