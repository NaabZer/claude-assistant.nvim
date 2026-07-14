local M = {}

M.defaults = {
  prompts = {
    review = "Review this for bugs and logic flaws:",
    explain = "Explain this and give usage examples:",
    explain_file = nil, -- nil => falls back to prompts.explain
    review_diff = "Review these changes for bugs and logic flaws:",
  },
  keymaps = {
    enable = false, -- do not map by default
    review = "<leader>cr",
    explain = "<leader>ce",
    paste = "<leader>cp", -- paste selection into prompt, no submit
    explain_file = "<leader>cE", -- explain the whole current file
    quicksend_insert = "<C-s>", -- insert-mode: send current line, clear it, stay in insert
    quicksend = "<leader>cs", -- visual/motion: send raw selection, delete it once sent
    review_diff = "<leader>cR", -- review the uncommitted diff
  },
  reference = {
    linewise = "@%s#L%s", -- whole-line selection: sent bare, alone (path, lines)
    charwise = "( @%s#L%s )", -- partial selection: appended after wrapped text (path, lines)
  },
  role_prompt = nil, -- nil => use the built-in default (commit 5)
  manage_claudecode = false, -- opt-in: configure claudecode's terminal_cmd for us
  claudecode = {}, -- passthrough opts when manage_claudecode = true
}

M.options = vim.deepcopy(M.defaults)

return M
