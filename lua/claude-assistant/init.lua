local M = {}

local config = require("claude-assistant.config")

-- Returns the `claude --append-system-prompt <role>` terminal_cmd string using
-- the configured role_prompt (or the built-in default). Useful when wiring
-- claudecode.setup() manually instead of setting manage_claudecode = true.
function M.terminal_cmd()
  return require("claude-assistant.role").terminal_cmd(config.options.role_prompt)
end

function M.setup(opts)
  -- hard dependency + version guards
  if vim.fn.has("nvim-0.10") == 0 then
    vim.notify("[claude-assistant] requires Neovim >= 0.10", vim.log.levels.ERROR)
    return
  end
  local ok = pcall(require, "claudecode")
  if not ok then
    vim.notify("[claude-assistant] requires coder/claudecode.nvim to be installed", vim.log.levels.ERROR)
    return
  end
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), opts or {})
  require("claude-assistant.commands").register() -- module defined in commit 4

  -- Opt-in: let the companion own claudecode's terminal_cmd so the assistant role
  -- is injected via --append-system-prompt on every launch. Off by default.
  if config.options.manage_claudecode then
    require("claudecode").setup(vim.tbl_deep_extend("force", config.options.claudecode or {}, {
      terminal_cmd = M.terminal_cmd(),
    }))
  end
end

return M
