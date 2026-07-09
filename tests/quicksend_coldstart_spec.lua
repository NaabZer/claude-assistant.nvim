-- Headless-nvim harness for M.send_line_insert's guarded-clear logic
-- (lua/claude-assistant/send.lua). Run with: nvim -l tests/quicksend_coldstart_spec.lua
--
-- send_line_insert() must only clear the current line once the send is CONFIRMED
-- to have reached an already-open pane (ok == true AND existed == true). On cold
-- start (existed == false) or a failed send (ok == false), the line -- the user's
-- only copy of what they typed -- must be kept untouched.

-- Resolve the plugin root from this script's own path so it works regardless
-- of the caller's cwd, then make `require("claude-assistant.send")` and
-- `require("harness")` resolvable.
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local root = script_dir .. "../"
package.path = script_dir .. "?.lua;" .. root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local harness = require("harness")
local fail, pass = harness.fail, harness.pass

-- Stub claudecode.terminal BEFORE requiring send.lua. `stub` is mutated between
-- cases so a single preload (require caches the module) can drive both the
-- existed==false (cold start) and ok==false (failed send) paths.
local stub = {
  existed = true,
  ok = true,
}
local calls = {
  ensure_visible = 0,
  send_to_terminal = {},
}

package.preload["claudecode.terminal"] = function()
  return {
    get_active_terminal_bufnr = function()
      return stub.existed and 1 or nil
    end,
    ensure_visible = function()
      calls.ensure_visible = calls.ensure_visible + 1
    end,
    send_to_terminal = function(payload, send_opts)
      table.insert(calls.send_to_terminal, { payload = payload, send_opts = send_opts })
      return stub.ok
    end,
  }
end

local send = require("claude-assistant.send")

if type(send.send_line_insert) ~= "function" then
  fail("send.lua does not expose M.send_line_insert")
end

-- Create a scratch buffer with a single known line, make it current (buffer AND
-- window), and park the cursor on that line -- send_line_insert reads the
-- CURRENT buffer/window via nvim_get_current_buf()/nvim_win_get_cursor().
local function make_scratch(line_text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line_text })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

local function line_of(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end

-- Case 1: cold start (existed == false) -> fire() takes the vim.defer_fn(go, 250)
-- path. Pump the event loop until send_to_terminal has actually been invoked,
-- then assert the line is untouched.
do
  stub.existed = false
  stub.ok = true
  calls.send_to_terminal = {}
  local text = "cold start line"
  local buf = make_scratch(text)

  send.send_line_insert()

  local fired = vim.wait(500, function()
    return #calls.send_to_terminal >= 1
  end, 10)

  if not fired then
    fail("cold start: send_to_terminal was not called within 500ms")
  end
  local cur = line_of(buf)
  if cur ~= text then
    fail('cold start: line was modified, expected untouched "' .. text .. '", got "' .. tostring(cur) .. '"')
  end
  pass("cold start (existed=false): line kept untouched, send_to_terminal called")
end

-- Case 2: failed send (ok == false, existed == true) -> immediate path (no
-- defer), so no need to pump the loop. Assert the line is untouched.
do
  stub.existed = true
  stub.ok = false
  calls.send_to_terminal = {}
  local text = "failed send line"
  local buf = make_scratch(text)

  send.send_line_insert()

  local cur = line_of(buf)
  if cur ~= text then
    fail('failed send: line was modified, expected untouched "' .. text .. '", got "' .. tostring(cur) .. '"')
  end
  if #calls.send_to_terminal ~= 1 then
    fail("failed send: send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 1")
  end
  pass("failed send (ok=false, existed=true): line kept untouched")
end

-- Case 3 (happy path): ok == true, existed == true -> the line SHOULD be cleared.
do
  stub.existed = true
  stub.ok = true
  calls.send_to_terminal = {}
  local text = "happy path line"
  local buf = make_scratch(text)

  send.send_line_insert()

  local cur = line_of(buf)
  if cur ~= "" then
    fail('happy path: line was not cleared, expected "", got "' .. tostring(cur) .. '"')
  end
  if #calls.send_to_terminal ~= 1 then
    fail("happy path: send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 1")
  end
  pass("happy path (ok=true, existed=true): line cleared")
end

-- Case 4 (bonus): empty current line -> no send at all, silent return.
do
  stub.existed = true
  stub.ok = true
  calls.send_to_terminal = {}
  local buf = make_scratch("")

  send.send_line_insert()

  if #calls.send_to_terminal ~= 0 then
    fail("empty line: send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 0")
  end
  pass("empty line: no send")
end

os.exit(0, true)
