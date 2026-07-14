local M = {}
local send = require("claude-assistant.send")

local function operator(action)
  -- expr mapping: stash the opfunc, then g@ waits for a motion
  _G.__claude_assistant_opfunc = send.make_opfunc(action)
  vim.o.operatorfunc = "v:lua.__claude_assistant_opfunc"
  return "g@"
end

-- Install an opt-in default keymap only when the user enabled defaults. remap=true is
-- REQUIRED for <Plug> RHS values to expand (vim.keymap.set is noremap by default).
local function maybe_map(cfg, mode, lhs, rhs)
  -- lhs may be false/nil when the user opts out of a single default map
  -- (keymaps = { enable = true, paste = false }); skip those instead of erroring.
  if cfg.keymaps.enable and lhs then
    vim.keymap.set(mode, lhs, rhs, { remap = true, silent = true })
  end
end

-- Register a single-shot normal-mode command (no visual/operator/range): a <Plug>
-- mapping, a user command, and an opt-in default keymap. `suffix` names both the
-- <Plug> and the :ClaudeAssistant<suffix> command; `keymap_key` indexes cfg.keymaps.
local function register_single_shot(cfg, suffix, keymap_key, fn)
  local plug = "<Plug>(ClaudeAssistant" .. suffix .. ")"
  vim.keymap.set("n", plug, fn, { silent = true })
  vim.api.nvim_create_user_command("ClaudeAssistant" .. suffix, fn, {})
  maybe_map(cfg, "n", cfg.keymaps[keymap_key], plug)
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

    -- Opt-in default keymap.
    maybe_map(cfg, { "n", "x" }, cfg.keymaps[action], plug)
  end

  -- cE / cR: single-shot normal-mode commands (no selection/motion/range) -- cE explains
  -- the whole file, cR sends the working-tree diff.
  register_single_shot(cfg, "ExplainFile", "explain_file", function() send.explain_file() end)
  register_single_shot(cfg, "ReviewDiff", "review_diff", function() send.review_diff() end)

  -- Insert-mode quick-send: keystroke-driven, no selection/motion/range involved, so
  -- no <Plug> or user command -- the opt-in keymap below is the only entrypoint.
  maybe_map(cfg, "i", cfg.keymaps.quicksend_insert,
    function() require("claude-assistant.send").send_line_insert() end)

  -- Visual/motion quick-send: raw send + delete-on-confirmed-send. Semantically distinct
  -- from the {review,explain,paste} family (no prompt/wrap/reference, and it mutates the
  -- buffer), so it's registered on its own here rather than in that loop, with its own
  -- opfunc global so it never clashes with operator()'s.
  local quick_plug = "<Plug>(ClaudeAssistantQuickSend)"

  vim.keymap.set("x", quick_plug,
    ":<C-u>lua require('claude-assistant.send').send_quick_visual()<CR>", { silent = true })
  vim.keymap.set("n", quick_plug, function()
    _G.__claude_assistant_quick_opfunc = send.make_quick_opfunc()
    vim.o.operatorfunc = "v:lua.__claude_assistant_quick_opfunc"
    return "g@"
  end, { expr = true, silent = true })

  vim.api.nvim_create_user_command("ClaudeAssistantQuickSend",
    function() send.send_quick_visual() end, { range = true })

  maybe_map(cfg, { "n", "x" }, cfg.keymaps.quicksend, quick_plug)
end

return M
