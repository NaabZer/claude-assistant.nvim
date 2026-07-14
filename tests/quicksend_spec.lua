-- Headless-nvim harness for lua/claude-assistant/send.lua.
-- Run with: nvim -l tests/quicksend_spec.lua
--
-- Keep this minimal: it currently only covers the `fire` helper's on_result
-- contract. Later commits add more cases as new senders land.

-- Resolve the plugin root from this script's own path so it works regardless
-- of the caller's cwd, then make `require("claude-assistant.send")` and
-- `require("harness")` resolvable.
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local root = script_dir .. "../"
package.path = script_dir .. "?.lua;" .. root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local harness = require("harness")
local fail, pass = harness.fail, harness.pass

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

-- ---------------------------------------------------------------------------------------
-- fire(): submit decouple -- claudecode bundles the bracketed paste and its own CR in one
-- chansend with no gap, so a warm TUI can swallow the CR into the paste block. fire() now
-- NEVER lets claudecode submit (always passes submit=false through), and instead sends its
-- own "\r" straight to the terminal channel after SUBMIT_DELAY_MS, so it can't race the
-- paste. Give the stubbed active bufnr (1) a fake terminal channel and stub vim.fn.chansend
-- to record calls instead of writing to a real PTY.
-- ---------------------------------------------------------------------------------------

do
  local fake_chan = 4242
  vim.b[1].terminal_job_id = fake_chan

  local chansend_calls = {}
  local orig_chansend = vim.fn.chansend
  vim.fn.chansend = function(chan, data)
    table.insert(chansend_calls, { chan = chan, data = data })
    return 1
  end

  -- Case A: submit=true -- fire() must pass submit=false through to send_to_terminal (it
  -- now owns the Enter itself) and must send its own "\r" to the terminal channel after
  -- the paste, once SUBMIT_DELAY_MS has elapsed.
  calls.send_to_terminal = {}
  send._fire("hi\n", { submit = true, focus = false })

  local fired = vim.wait(200, function()
    return #chansend_calls > 0
  end, 10)

  if not fired then
    fail("submit decouple: vim.fn.chansend was not called within 200ms")
  end
  if #chansend_calls ~= 1 then
    fail("submit decouple: chansend called " .. #chansend_calls .. " times, expected 1")
  end
  if chansend_calls[1].chan ~= fake_chan then
    fail("submit decouple: chansend chan = " .. tostring(chansend_calls[1].chan) .. ", expected " .. fake_chan)
  end
  if chansend_calls[1].data ~= "\r" then
    fail('submit decouple: chansend data = "' .. tostring(chansend_calls[1].data) .. '", expected "\\r"')
  end
  if #calls.send_to_terminal ~= 1 then
    fail("submit decouple: send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 1")
  end
  if calls.send_to_terminal[1].send_opts.submit ~= false then
    fail(
      "submit decouple: send_to_terminal submit = "
        .. tostring(calls.send_to_terminal[1].send_opts.submit)
        .. ", expected false (fire() now owns the Enter)"
    )
  end
  pass("fire() submit=true: send_to_terminal called with submit=false, own \\r sent to the terminal channel")

  -- Case B: submit=false (paste path) -- fire() must NEVER auto-submit; no "\r" should
  -- ever reach chansend, even after waiting past SUBMIT_DELAY_MS.
  chansend_calls = {}
  calls.send_to_terminal = {}
  send._fire("hi\n", { submit = false, focus = true })

  vim.wait(120)

  local saw_cr = false
  for _, c in ipairs(chansend_calls) do
    if c.data == "\r" then
      saw_cr = true
    end
  end
  if saw_cr then
    fail("paste path: chansend was called with \\r, expected no auto-submit")
  end
  if #calls.send_to_terminal ~= 1 or calls.send_to_terminal[1].send_opts.submit ~= false then
    fail("paste path: send_to_terminal submit flag not preserved as false")
  end
  pass("fire() submit=false (paste): no auto-submit \\r sent to the terminal channel")

  vim.fn.chansend = orig_chansend
  vim.b[1].terminal_job_id = nil
end

-- ---------------------------------------------------------------------------------------
-- M._delete_region: the delete-math cases the whole commit hinges on. Each case builds a
-- fresh scratch buffer with known content, makes it CURRENT (getregion/getregionpos read
-- the current buffer), calls M._delete_region directly, and asserts the exact resulting
-- buffer content.
-- ---------------------------------------------------------------------------------------

if type(send._delete_region) ~= "function" then
  fail("send.lua does not expose M._delete_region")
end

local function make_scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function assert_lines(buf, expected, label)
  local got = buf_lines(buf)
  if #got ~= #expected then
    fail(label .. ": expected " .. #expected .. " lines, got " .. #got .. " (" .. table.concat(got, "|") .. ")")
  end
  for i, exp in ipairs(expected) do
    if got[i] ~= exp then
      fail(label .. ": line " .. i .. ' expected "' .. exp .. '", got "' .. tostring(got[i]) .. '"')
    end
  end
end

-- Case 1: charwise, single-byte -- delete a mid-line ASCII span.
do
  local buf = make_scratch({ "abcdefgh" })
  -- delete "cdef" (cols 3-6, 1-based), operator-style: exclusive=false
  local pos1 = { 0, 1, 3, 0 }
  local pos2 = { 0, 1, 6, 0 }
  send._delete_region(buf, pos1, pos2, "v", false)
  assert_lines(buf, { "abgh" }, "charwise single-byte")
  pass("charwise single-byte: mid-line ASCII span deleted exactly")
end

-- Case 2: charwise, MULTIBYTE -- last selected char is multibyte (the case this commit
-- hinges on). Line: local x = "h\xC3\xA9llo\xE2\x86\x92\xE4\xB8\x96\xE7\x95\x8C" i.e.
-- `local x = "héllo→世界"`. Select from "h" through the FULL "世" character (inclusive)
-- and delete it; the trailing "界\"" must survive untouched.
do
  local line = 'local x = "héllo→世界"'
  local buf = make_scratch({ line })
  local col_h = assert(line:find("h", 1, true))
  local shi_start = assert(line:find("世", 1, true))
  local shi_last_byte = shi_start + #"世" - 1 -- last byte of the multibyte "世" char
  local pos1 = { 0, 1, col_h, 0 }
  local pos2 = { 0, 1, shi_last_byte, 0 }
  send._delete_region(buf, pos1, pos2, "v", false) -- inclusive: deletes through "世"
  assert_lines(buf, { 'local x = "界"' }, "charwise multibyte")
  pass('charwise MULTIBYTE: "héllo→世" deleted, trailing "界\\"" survives intact')
end

-- Case 3: charwise inclusive vs exclusive end -- same positions, different `exclusive`.
-- Line: "abcdefgh". pos1 at col 3 ('c'), pos2 at col 6 ('f').
--   exclusive=false (operator '[ '] semantics): deletes through 'f'   -> "abgh"
--   exclusive=true  (a 'selection=exclusive' visual end):            -> stops one before 'f'
--                                                                        -> "abfgh"
do
  local line = "abcdefgh"
  local pos1 = { 0, 1, 3, 0 }
  local pos2 = { 0, 1, 6, 0 }

  local buf_incl = make_scratch({ line })
  send._delete_region(buf_incl, pos1, pos2, "v", false)
  assert_lines(buf_incl, { "abgh" }, "charwise inclusive end")
  pass("charwise inclusive end (exclusive=false): deletes through the last char")

  local buf_excl = make_scratch({ line })
  send._delete_region(buf_excl, pos1, pos2, "v", true)
  assert_lines(buf_excl, { "abfgh" }, "charwise exclusive end")
  pass("charwise exclusive end (exclusive=true): stops one before the last char")
end

-- Case 3b: charwise, MULTI-LINE -- delete spans three lines. getregionpos returns one
-- {start,end} segment PER LINE, and delete_region does a single spanning
-- nvim_buf_set_text(buf, srow, scol, erow, ecol, {}) call that joins the first line's
-- prefix with the last line's suffix, dropping the lines in between entirely.
do
  local buf = make_scratch({ "abcdefgh", "ijklmnop", "qrstuvwx" })
  -- delete from line 1 col 3 ('c') through line 3 col 5 ('u'), operator-style: exclusive=false
  local pos1 = { 0, 1, 3, 0 }
  local pos2 = { 0, 3, 5, 0 }
  send._delete_region(buf, pos1, pos2, "v", false)
  assert_lines(buf, { "abvwx" }, "charwise multi-line")
  pass("charwise multi-line: first-line prefix joins last-line suffix")
end

-- Case 4: linewise -- delete whole lines out of a multi-line buffer.
do
  local buf = make_scratch({ "one", "two", "three", "four" })
  local pos1 = { 0, 2, 1, 0 }
  local pos2 = { 0, 3, 1, 0 }
  send._delete_region(buf, pos1, pos2, "V", false)
  assert_lines(buf, { "one", "four" }, "linewise")
  pass("linewise: whole line range deleted, remaining buffer intact")
end

-- Case 5: blockwise is send-only -- M._delete_region must never be reached for "\22" on
-- the quick_send path (the guard lives in quick_send itself, before delete_region is
-- called). Drive it through the public entrypoint with a stubbed visualmode() so we
-- exercise the actual guard, not just the low-level helper.
do
  local buf = make_scratch({ "abcdefgh", "ijklmnop" })
  vim.cmd("normal! gg0")
  vim.fn.setpos("'<", { 0, 1, 1, 0 })
  vim.fn.setpos("'>", { 0, 2, 3, 0 })

  local orig_visualmode = vim.fn.visualmode
  vim.fn.visualmode = function()
    return "\22" -- CTRL-V: blockwise
  end

  calls.send_to_terminal = {}
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  send.send_quick_visual()

  vim.fn.visualmode = orig_visualmode
  vim.notify = orig_notify

  assert_lines(buf, { "abcdefgh", "ijklmnop" }, "blockwise send-only")

  local saw_blockwise_notice = false
  for _, n in ipairs(notified) do
    if n.msg:find("blockwise", 1, true) then
      saw_blockwise_notice = true
    end
  end
  if not saw_blockwise_notice then
    fail("blockwise quick-send did not notify 'blockwise: sent, not deleted'")
  end
  pass("blockwise: send_quick_visual sends but does NOT delete the region")
end

-- Case 6: charwise happy-path -- drive the confirmed-send delete through the PUBLIC
-- entrypoint (send_quick_visual), not the low-level helper. The stubbed
-- claudecode.terminal above yields existed=true / ok=true, so this exercises the
-- SYNCHRONOUS confirmed-send path end-to-end: send, then delete.
do
  local buf = make_scratch({ "abcdefgh" })
  vim.fn.setpos("'<", { 0, 1, 3, 0 })
  vim.fn.setpos("'>", { 0, 1, 6, 0 })

  local orig_visualmode = vim.fn.visualmode
  vim.fn.visualmode = function()
    return "v" -- charwise
  end

  calls.send_to_terminal = {}
  local orig_notify = vim.notify
  vim.notify = function() end

  send.send_quick_visual()

  vim.fn.visualmode = orig_visualmode
  vim.notify = orig_notify

  assert_lines(buf, { "abgh" }, "charwise happy-path")
  if #calls.send_to_terminal ~= 1 then
    fail("charwise happy-path: send_to_terminal called " .. #calls.send_to_terminal .. " times, expected 1")
  end
  pass("charwise happy-path: send_quick_visual sends and deletes the region")
end

os.exit(0, true)
