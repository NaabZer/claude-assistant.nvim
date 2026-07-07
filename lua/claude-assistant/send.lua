local M = {}

-- Extract the text of a region between two positions via the built-in
-- getregion(), which handles charwise / linewise / blockwise selections and
-- multi-byte text correctly (Neovim >= 0.10). Positions are getpos()-style
-- lists; regtype matches visualmode(): "v" charwise, "V" linewise, or the
-- blockwise CTRL-V byte. `exclusive` overrides getregion's default (which
-- follows 'selection'); pass false to force an inclusive end. When exclusive is
-- nil the key is absent, so getregion follows the user's 'selection' option.
local function region_text(pos1, pos2, regtype, exclusive)
  local lines = vim.fn.getregion(pos1, pos2, { type = regtype, exclusive = exclusive })
  return table.concat(lines, "\n")
end

-- action drives prompt prefix + submit behavior:
--   "review"/"explain" -> prefix + submit=true
--   "paste"            -> no prefix, submit=false, focus=true (type your own prompt)
local function do_send(action, text)
  if not text or text == "" then
    vim.notify("[claude-assistant] nothing selected", vim.log.levels.WARN)
    return
  end
  local cfg = require("claude-assistant.config").options
  local prefix = cfg.prompts[action] -- nil for "paste"
  local payload = prefix and (prefix .. "\n" .. text) or text
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

-- Visual entrypoint. The x-mode mapping uses the :<C-u>...<CR> form so visual
-- mode is LEFT before this runs, committing '< '> and visualmode().
function M.send_visual(action)
  do_send(action, region_text(vim.fn.getpos("'<"), vim.fn.getpos("'>"), vim.fn.visualmode()))
end

-- Operator entrypoint: opfunc is invoked by g@ with kind = 'line'|'char'|'block'.
function M.make_opfunc(action)
  return function(kind)
    -- "\22" is the CTRL-V byte (0x16) that getregion/visualmode use for blockwise.
    local regtype = ({ line = "V", char = "v", block = "\22" })[kind] or "v"
    -- '[ and '] are always inclusive, regardless of 'selection', so force
    -- exclusive = false to avoid dropping the last char under selection=exclusive.
    do_send(action, region_text(vim.fn.getpos("'["), vim.fn.getpos("']"), regtype, false))
  end
end

return M
