local M = {}

local config = require("claude-assistant.config")

function M.setup(opts)
  -- hard dependency + version guards
  if vim.fn.has("nvim-0.7") == 0 then
    vim.notify("[claude-assistant] requires Neovim >= 0.7", vim.log.levels.ERROR)
    return
  end
  local ok = pcall(require, "claudecode")
  if not ok then
    vim.notify("[claude-assistant] requires coder/claudecode.nvim to be installed", vim.log.levels.ERROR)
    return
  end
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), opts or {})
  require("claude-assistant.commands").register() -- module defined in commit 4
  -- role wiring (manage_claudecode) added in commit 5
end

return M
