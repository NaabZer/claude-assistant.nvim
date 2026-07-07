local M = {}

M.defaults = {
  prompts = {
    review = "Review this for bugs and logic flaws:",
    explain = "Explain this and give usage examples:",
  },
  keymaps = {
    enable = false, -- do not map by default
    review = "<leader>cr",
    explain = "<leader>ce",
    paste = "<leader>cp", -- paste selection into prompt, no submit
  },
  role_prompt = nil, -- nil => use the built-in default (commit 5)
  manage_claudecode = false, -- opt-in: configure claudecode's terminal_cmd for us
  claudecode = {}, -- passthrough opts when manage_claudecode = true
}

M.options = vim.deepcopy(M.defaults)

return M
