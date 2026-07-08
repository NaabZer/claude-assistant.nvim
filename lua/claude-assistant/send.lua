local M = {}

-- Extract the text of a region between two positions via getregion() (Neovim >= 0.10),
-- which handles charwise/linewise/blockwise and multi-byte text. exclusive overrides
-- getregion's default (which follows 'selection'); pass false to force an inclusive end.
local function region_text(pos1, pos2, regtype, exclusive)
  local lines = vim.fn.getregion(pos1, pos2, { type = regtype, exclusive = exclusive })
  return table.concat(lines, "\n")
end

-- Workspace-relative path + line spec for the current buffer, or nil for an unnamed
-- buffer (no file to reference). `lines` is "54" for one line or "54-58" for a range.
local function file_and_lines(startln, endln)
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  local path = vim.fn.fnamemodify(name, ":.") -- relative to cwd when the file is under it
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

  local terminal = require("claudecode.terminal")
  local existed = terminal.get_active_terminal_bufnr() ~= nil
  terminal.ensure_visible() -- create/show the Claude pane without stealing focus
  local function fire()
    local ok = terminal.send_to_terminal(payload, {
      submit = action ~= "paste", -- paste inserts without sending
      focus = action == "paste", -- land in the prompt to keep typing
    })
    if not ok then
      vim.notify(
        "[claude-assistant] send failed - needs the native/snacks provider and a Claude pane",
        vim.log.levels.ERROR
      )
    end
  end
  -- Cold start: ensure_visible() just spawned Claude; its TUI prompt is not ready,
  -- so writing immediately can drop the first message. Defer only in that case.
  if existed then
    fire()
  else
    vim.defer_fn(fire, 250)
  end
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

return M
