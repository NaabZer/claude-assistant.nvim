local M = {}

-- Extract the text of a region between two positions via getregion() (Neovim >= 0.10),
-- which handles charwise/linewise/blockwise and multi-byte text. exclusive overrides
-- getregion's default (which follows 'selection'); pass false to force an inclusive end.
local function region_text(pos1, pos2, regtype, exclusive)
  local lines = vim.fn.getregion(pos1, pos2, { type = regtype, exclusive = exclusive })
  return table.concat(lines, "\n")
end

-- Workspace-relative path of the current buffer, or nil for an unnamed buffer.
local function current_file_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":.") -- relative to cwd when the file is under it
end

-- Workspace-relative path + line spec for the current buffer, or nil for an unnamed
-- buffer (no file to reference). `lines` is "54" for one line or "54-58" for a range.
local function file_and_lines(startln, endln)
  local path = current_file_path()
  if not path then
    return nil
  end
  local lines = (startln == endln) and tostring(startln) or (startln .. "-" .. endln)
  return path, lines
end

-- Wrap charwise text: inline `code` for one line, a fenced block (tagged with the
-- buffer's filetype) for many.
local function wrap_code(text)
  if text:find("\n", 1, true) then
    return "```" .. (vim.bo.filetype or "") .. "\n" .. text .. "\n```"
  end
  return "`" .. text .. "`"
end

-- show the pane and send; on_result(ok, existed) fires after the attempt.
local function fire(payload, send_opts, on_result)
  local terminal = require("claudecode.terminal")
  local existed = terminal.get_active_terminal_bufnr() ~= nil
  terminal.ensure_visible()
  local function go()
    local ok = terminal.send_to_terminal(payload, send_opts)
    if not ok then
      vim.notify(
        "[claude-assistant] send failed - needs the native/snacks provider and a Claude pane",
        vim.log.levels.ERROR
      )
    end
    if on_result then
      on_result(ok, existed)
    end
  end
  if existed then
    go()
  else
    vim.defer_fn(go, 250)
  end
end

M._fire = fire

-- Register-safe, undoable deletion of a region -- called ONLY from quick_send's on_result,
-- after a CONFIRMED send (never on cold start / failed send / blockwise). Uses the buffer
-- API exclusively (nvim_buf_set_lines / nvim_buf_set_text), never a `d`-motion, so the
-- unnamed register is untouched.
local function delete_region(buf, pos1, pos2, regtype, exclusive)
  if regtype == "V" then
    -- Linewise: drop the whole line range.
    local startln = math.min(pos1[2], pos2[2])
    local endln = math.max(pos1[2], pos2[2])
    vim.api.nvim_buf_set_lines(buf, startln - 1, endln, false, {})
    return
  end

  -- Charwise: getregionpos (Neovim >= 0.10) returns byte positions honoring
  -- type/exclusive/multibyte, so we don't hand-roll the inclusive-BYTE -> exclusive-col
  -- conversion. For a multi-line charwise region it returns one {start, end} segment PER
  -- LINE; the delete rect spans the first segment's start to the last segment's end, and
  -- nvim_buf_set_text joins the first line's prefix with the last line's suffix in one
  -- call -- exactly like a charwise `d`. Empirically confirmed (against a multibyte line,
  -- e.g. "h\xC3\xA9llo\xE2\x86\x92\xE4\xB8\x96\xE7\x95\x8C"): each returned column is the
  -- LAST byte (1-based) of the boundary character, which numerically equals the 0-based
  -- EXCLUSIVE end column nvim_buf_set_text expects (1-based inclusive index X == 0-based
  -- exclusive index X), so it's used as-is with no extra +/-1.
  local regions = vim.fn.getregionpos(pos1, pos2, { type = regtype, exclusive = exclusive })
  if not regions or #regions == 0 then
    return
  end
  local first, last = regions[1][1], regions[#regions][2]
  local srow, scol = first[2] - 1, first[3] - 1
  local erow, ecol = last[2] - 1, last[3]
  vim.api.nvim_buf_set_text(buf, srow, scol, erow, ecol, {})
end

M._delete_region = delete_region

-- opts: { pos1, pos2, regtype, exclusive, linewise }
local function do_send(action, opts)
  local cfg = require("claude-assistant.config").options

  local startln = math.min(opts.pos1[2], opts.pos2[2])
  local endln = math.max(opts.pos1[2], opts.pos2[2])
  local path, lines = file_and_lines(startln, endln)

  local body
  if opts.linewise and path then
    -- Whole-line selection: send just the bare @file#Lx-y reference; Claude reads
    -- the exact lines from the file.
    body = string.format(cfg.reference.linewise, path, lines)
  else
    -- Charwise (or a linewise selection in an unnamed buffer): send the actual text,
    -- wrapped as code, plus the reference in spaced parens so the @-mention still
    -- expands (tight "(@..)" does NOT expand; "( @.. )" does).
    local text = region_text(opts.pos1, opts.pos2, opts.regtype, opts.exclusive)
    if not text or text == "" then
      vim.notify("[claude-assistant] nothing selected", vim.log.levels.WARN)
      return
    end
    body = wrap_code(text)
    if path then
      local sep = text:find("\n", 1, true) and "\n" or " "
      body = body .. sep .. string.format(cfg.reference.charwise, path, lines)
    end
  end

  local prefix = cfg.prompts[action] -- nil for "paste"
  local sep = body:find("\n", 1, true) and "\n" or " "
  local payload = prefix and (prefix .. sep .. body) or body

  -- claudecode.send_to_terminal only bracketed-pastes MULTI-line sends; a single-line
  -- payload is typed char-by-char, so an @-mention in it opens Claude Code's interactive
  -- file-mention menu (which drops characters and eats the submit Enter). Guarantee a
  -- newline so the whole payload is bracketed-pasted as literal text and submits cleanly.
  if not payload:find("\n", 1, true) then
    payload = payload .. "\n"
  end

  fire(payload, { submit = action ~= "paste", focus = action == "paste" })
end

-- Visual entrypoint. The x-mode mapping uses the :<C-u>...<CR> form so visual mode is
-- LEFT before this runs, committing '< '> and visualmode(). No exclusive arg: the
-- '< '> marks reflect the user's 'selection', so let getregion follow it.
function M.send_visual(action)
  local regtype = vim.fn.visualmode()
  do_send(action, {
    pos1 = vim.fn.getpos("'<"),
    pos2 = vim.fn.getpos("'>"),
    regtype = regtype,
    exclusive = nil,
    linewise = regtype == "V",
  })
end

-- Operator entrypoint: opfunc invoked by g@ with kind = 'line'|'char'|'block'.
function M.make_opfunc(action)
  return function(kind)
    -- "\22" is the CTRL-V byte (0x16) that getregion/visualmode use for blockwise.
    local regtype = ({ line = "V", char = "v", block = "\22" })[kind] or "v"
    do_send(action, {
      pos1 = vim.fn.getpos("'["),
      pos2 = vim.fn.getpos("']"),
      regtype = regtype,
      exclusive = false, -- '[ '] are always inclusive regardless of 'selection'
      linewise = kind == "line",
    })
  end
end

-- Whole-file entrypoint: no selection involved, just the explain prompt plus a bare
-- whole-file @-mention. Claude Code expands it and reads the entire file itself.
function M.explain_file()
  local cfg = require("claude-assistant.config").options
  local path = current_file_path()
  if not path then
    vim.notify("[claude-assistant] no file to explain (unnamed buffer)", vim.log.levels.WARN)
    return
  end
  local prompt = cfg.prompts.explain_file or cfg.prompts.explain
  local payload = prompt .. "\n@" .. path .. "\n" -- multi-line -> bracketed paste
  fire(payload, { submit = true, focus = false })
end

-- Uncommitted-diff review: send the working tree diff as raw text (no @-reference, no
-- code wrap) with a configurable review prompt, submitted. Prefers `rtk git diff` when
-- rtk is installed (it may add context on top of the raw diff), else falls back to
-- `git diff HEAD`. Degrades gracefully: no repo / command error vs. a genuinely empty
-- diff are distinguished so the user isn't left guessing, and an empty prompt is never
-- sent.
function M.review_diff()
  local cfg = require("claude-assistant.config").options
  local cmd = (vim.fn.executable("rtk") == 1) and { "rtk", "git", "diff" } or { "git", "diff", "HEAD" }
  local res = vim.system(cmd, { text = true }):wait()
  local diff = (res.stdout or ""):gsub("%s+$", "")
  if diff == "" then
    -- Empty stdout => no changes, regardless of exit code (rtk/git differ on a clean diff).
    if res.code ~= 0 then
      vim.notify("[claude-assistant] diff failed: " .. (res.stderr or ""), vim.log.levels.WARN)
    else
      vim.notify("[claude-assistant] no changes to review", vim.log.levels.INFO)
    end
    return
  end
  local payload = cfg.prompts.review_diff .. "\n" .. diff .. "\n" -- multi-line -> bracketed paste
  fire(payload, { submit = true, focus = false })
end

-- Insert-mode quick-send: fire the current line as-is, then clear it (staying in
-- insert mode) so the line becomes a scratch prompt buffer. Only clears once the
-- send is CONFIRMED to have gone to an already-open pane -- on cold start (or a
-- failed send) the text is kept, since it's the only copy the user has typed.
function M.send_line_insert()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1 -- 0-indexed
  local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  -- Strip leading indentation: the whitespace is editor auto-indent, not part of the
  -- prompt. `indent` is kept so we can restore it after clearing (below).
  local indent, prompt = text:match("^(%s*)(.*)$")
  if prompt == "" then -- blank or whitespace-only line: nothing to send
    return
  end
  -- Force-append a newline so a single-line payload containing "@" is bracketed-pasted
  -- rather than typed char-by-char into Claude's interactive mention menu (same reason
  -- do_send guarantees a trailing newline).
  fire(prompt .. "\n", { submit = true, focus = false }, function(ok, existed)
    if ok and existed and vim.bo[buf].modifiable then
      -- The cursor may have moved, or the user may have kept typing during the
      -- cold-start defer; only clear if the line still matches what was sent.
      local cur = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      if cur == text then
        -- Keep the indentation (not a bare "") and park the cursor after it, so the
        -- next line continues at the same level instead of snapping to column 0.
        vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { indent }) -- register-safe, undoable
        if vim.api.nvim_get_current_win() == win then
          vim.api.nvim_win_set_cursor(win, { row + 1, #indent })
        end
      end
    else
      vim.notify("[claude-assistant] Sent - Claude pane was starting, text kept.", vim.log.levels.INFO)
    end
  end)
end

-- Visual/motion quick-send: send the RAW region text as-is (no prompt prefix, no code
-- wrap, no @-reference) and DELETE the region -- but ONLY once the send is CONFIRMED to
-- have reached an already-open pane (same guard as send_line_insert). Cold start / failed
-- send keeps the text; blockwise and read-only/special buffers are send-only (no delete).
local function quick_send(pos1, pos2, regtype, exclusive)
  local text = region_text(pos1, pos2, regtype, exclusive)
  if not text or text == "" then
    vim.notify("[claude-assistant] nothing selected", vim.log.levels.WARN)
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  -- Keep the force-newline so a single-line raw payload with an embedded @ is
  -- bracketed-pasted, not typed into Claude's mention menu (same rule as do_send).
  local payload = text:find("\n", 1, true) and text or (text .. "\n")
  fire(payload, { submit = true, focus = false }, function(ok, existed)
    if not (ok and existed) then
      vim.notify("[claude-assistant] Sent - Claude pane was starting, text kept.", vim.log.levels.INFO)
      return
    end
    if not vim.bo[buf].modifiable then
      return -- read-only/special buffer: send-only
    end
    if regtype == "\22" then
      vim.notify("[claude-assistant] blockwise: sent, not deleted", vim.log.levels.INFO)
      return
    end
    delete_region(buf, pos1, pos2, regtype, exclusive)
  end)
end

-- Visual entrypoint (see M.send_visual for the :<C-u>...<CR> mark-commit rationale).
function M.send_quick_visual()
  local regtype = vim.fn.visualmode()
  quick_send(vim.fn.getpos("'<"), vim.fn.getpos("'>"), regtype, nil)
end

-- Operator entrypoint: opfunc invoked by g@ with kind = 'line'|'char'|'block'.
function M.make_quick_opfunc()
  return function(kind)
    local regtype = ({ line = "V", char = "v", block = "\22" })[kind] or "v"
    quick_send(vim.fn.getpos("'["), vim.fn.getpos("']"), regtype, false)
  end
end

return M
