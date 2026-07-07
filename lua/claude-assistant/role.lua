local M = {}

M.DEFAULT_ROLE = table.concat({
  "You are a pair-programming assistant embedded in Neovim.",
  "The user writes their own code; you assist.",
  "Review selections, answer questions, and give docs and usage examples -",
  "code examples are welcome (Stack-Overflow style).",
  "Do NOT autonomously edit the user's files or run edit tools unless explicitly asked;",
  "prefer explaining and showing example code the user applies themselves.",
}, " ")

-- Compose a terminal_cmd string with the role baked in. shellescape keeps the
-- role as one shell arg; claudecode.nvim parses terminal_cmd with its own
-- POSIX-style shell_split (single-quoted content is literal) before spawning via
-- termopen, so single-quote shellescape output round-trips back to the exact role.
function M.terminal_cmd(role)
  role = role or M.DEFAULT_ROLE
  return "claude --append-system-prompt " .. vim.fn.shellescape(role)
end

return M
