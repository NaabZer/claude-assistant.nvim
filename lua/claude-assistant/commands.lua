local M = {}
local send = require("claude-assistant.send")

local function operator(action)
  -- expr mapping: stash the opfunc, then g@ waits for a motion
  _G.__claude_assistant_opfunc = send.make_opfunc(action)
  vim.o.operatorfunc = "v:lua.__claude_assistant_opfunc"
  return "g@"
end

function M.register()
  local cfg = require("claude-assistant.config").options

  for _, action in ipairs({ "review", "explain", "paste" }) do
    local suffix = action:gsub("^%l", string.upper)
    local plug = "<Plug>(ClaudeAssistant" .. suffix .. ")"

    -- <Plug> mappings (always available).
    -- Visual: :<C-u> leaves visual mode so '< '> (and visualmode()) are committed
    -- before send_visual reads them. A bare function map would read STALE marks.
    vim.keymap.set("x", plug,
      string.format(":<C-u>lua require('claude-assistant.send').send_visual('%s')<CR>", action),
      { silent = true })
    -- Normal: expr map sets operatorfunc and returns g@ so the next motion picks the range.
    vim.keymap.set("n", plug, function() return operator(action) end, { expr = true, silent = true })

    -- Range-capable user command (visual range -> '< '>).
    vim.api.nvim_create_user_command("ClaudeAssistant" .. suffix,
      function() send.send_visual(action) end, { range = true })

    -- Opt-in default keymap. remap = true is REQUIRED so the <Plug> RHS expands
    -- (vim.keymap.set is noremap by default, under which <Plug> does not fire).
    if cfg.keymaps.enable then
      vim.keymap.set({ "n", "x" }, cfg.keymaps[action], plug, { remap = true, silent = true })
    end
  end
end

return M
