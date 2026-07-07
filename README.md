# claude-assistant.nvim

An **assistant companion plugin** for Neovim, built on top of
[coder/claudecode.nvim](https://github.com/coder/claudecode.nvim).

You write your own code. `claude-assistant.nvim` sends a visual selection, or
a normal-mode motion / text object, to a running Claude Code pane as a
composed review/explain prompt — or pastes it into the prompt unsubmitted so
you can ask your own question around it. Claude is constrained to an
assistant role: it reviews, explains, and answers, but does not autonomously
edit your buffers. Nothing this plugin does ever touches your files directly;
`claudecode.nvim` is the transport, this plugin only composes prompts and
sends them to the Claude pane.

## Requirements

- [coder/claudecode.nvim](https://github.com/coder/claudecode.nvim) — this is
  the transport layer; `claude-assistant.nvim` has no functionality without
  it.
- Neovim >= 0.10 (the plugin uses `vim.fn.getregion()` to extract visual /
  motion ranges).
- claudecode.nvim's terminal provider must be `native` or `snacks`. Sending is
  inert on the `external` and `none` providers, since there is no in-editor
  pane for the plugin to write into.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "naabzer/nvim-claude-assistant", -- adjust to the actual repo path
  dependencies = { "coder/claudecode.nvim" },
  opts = {},
}
```

`opts = {}` (or an explicit `require("claude-assistant").setup({})` call) is
required — `setup()` is what registers the `:ClaudeAssistant*` commands and
`<Plug>` mappings. Without calling it, the plugin does nothing.

## Configuration

Full list of options with their defaults:

```lua
require("claude-assistant").setup({
  prompts = {
    review = "Review this for bugs and logic flaws:",
    explain = "Explain this and give usage examples:",
  },
  keymaps = {
    enable = false,     -- do not install the default keymaps below
    review = "<leader>cr",
    explain = "<leader>ce",
    paste = "<leader>cp",
  },
  role_prompt = nil,       -- nil => use the built-in default assistant role
  manage_claudecode = false, -- opt-in: let this plugin call claudecode.setup() for you
  claudecode = {},         -- passthrough opts merged into claudecode.setup() (see below)
})
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `prompts.review` | `string` | `"Review this for bugs and logic flaws:"` | Instruction prefix prepended to the sent text for `:ClaudeAssistantReview`. |
| `prompts.explain` | `string` | `"Explain this and give usage examples:"` | Instruction prefix prepended to the sent text for `:ClaudeAssistantExplain`. |
| `keymaps.enable` | `boolean` | `false` | Whether to install the default keymaps below on top of the `<Plug>` mappings. |
| `keymaps.review` | `string` | `"<leader>cr"` | `lhs` used for the review action when `keymaps.enable = true`. |
| `keymaps.explain` | `string` | `"<leader>ce"` | `lhs` used for the explain action when `keymaps.enable = true`. |
| `keymaps.paste` | `string` | `"<leader>cp"` | `lhs` used for the paste action when `keymaps.enable = true`. |
| `role_prompt` | `string \| nil` | `nil` | Overrides the assistant role text used with `--append-system-prompt`. `nil` uses the plugin's built-in default role. Only has an effect if you use the role injection described below. |
| `manage_claudecode` | `boolean` | `false` | Opt-in. When `true`, the plugin calls `claudecode.setup()` for you, wiring a `terminal_cmd` that injects the assistant role on every Claude launch. |
| `claudecode` | `table` | `{}` | Passthrough table merged into `claudecode.setup()` when `manage_claudecode = true` (see below). Ignored otherwise. |

`prompts.review` and `prompts.explain` are only used by their respective
commands; `:ClaudeAssistantPaste` sends the raw selection with no prefix (see
[Usage](#usage)).

## Assistant role injection

Claude's assistant role — "review, explain, don't auto-edit" — is injected
via `claude --append-system-prompt <role>` on the `terminal_cmd` that
claudecode.nvim uses to spawn Claude. This uses `--append-system-prompt`
rather than a Claude Code skill or `CLAUDE.md` entry because it is enforced
at the process level, deterministically, on every single launch: a skill or
`CLAUDE.md` file can be read, ignored, or superseded once a session starts,
but there's no way to *force* a session to load a given role the moment it
starts other than baking it into the launch command itself.

There are two ways to wire this up:

### (a) Opt-in: let the plugin own claudecode's `terminal_cmd`

```lua
require("claude-assistant").setup({
  manage_claudecode = true,
  claudecode = {
    -- any other claudecode.nvim options you want, e.g.:
    terminal = { provider = "native" },
  },
  role_prompt = "You are a strict, terse code reviewer.", -- optional override
})
```

When `manage_claudecode = true`, `claude-assistant.nvim` calls
`claudecode.setup()` itself, merging your `claudecode` table with a
`terminal_cmd` that injects the role (using `role_prompt` if set, otherwise
the built-in default role). Do **not** also call `claudecode.setup()`
yourself in this mode — let the plugin call it once, for you.

### (b) Manual: wire your own `claudecode.setup()`

If you'd rather keep full control of `claudecode.setup()`, leave
`manage_claudecode = false` (the default) and compose the `terminal_cmd`
yourself:

```lua
require("claudecode").setup({
  terminal_cmd = require("claude-assistant.role").terminal_cmd(),
  terminal = { provider = "native" },
})
```

`require("claude-assistant").terminal_cmd()` (zero-arg) is also available as
a convenience accessor — it returns the same composed command string, using
whatever `role_prompt` you passed to `claude-assistant.nvim`'s own `setup()`.

## Usage

### Commands

All three commands accept a visual range (`'<,'>`), which is populated
automatically when invoked from visual mode:

| Command | Behavior |
| --- | --- |
| `:ClaudeAssistantReview` | Sends `prompts.review` + the selection, submitted immediately. |
| `:ClaudeAssistantExplain` | Sends `prompts.explain` + the selection, submitted immediately. |
| `:ClaudeAssistantPaste` | Inserts the raw selection into the Claude prompt **without** submitting, and focuses the pane so you can type your own question around it. |

Example: `:'<,'>ClaudeAssistantReview`.

### `<Plug>` mappings

Every action registers a `<Plug>` mapping, always available regardless of
`keymaps.enable`:

- `<Plug>(ClaudeAssistantReview)`
- `<Plug>(ClaudeAssistantExplain)`
- `<Plug>(ClaudeAssistantPaste)`

Map these to keys of your choice, in both normal and visual mode:

```lua
vim.keymap.set({ "n", "x" }, "<leader>cr", "<Plug>(ClaudeAssistantReview)")
vim.keymap.set({ "n", "x" }, "<leader>ce", "<Plug>(ClaudeAssistantExplain)")
vim.keymap.set({ "n", "x" }, "<leader>cp", "<Plug>(ClaudeAssistantPaste)")
```

If you'd rather have the plugin install these for you with the defaults
shown in [Configuration](#configuration), set `keymaps.enable = true`.

### Visual selection vs. operator + motion

Each mapping works two ways:

- **Visual selection**: select text, then hit the mapping (e.g. select a
  block, then `<leader>cr`) to act on the selection.
- **Normal-mode operator**: hit the mapping first, then supply a motion or
  text object (e.g. `<leader>cr` then `ip` reviews the inner paragraph under
  the cursor; `<leader>ce` then `2j` explains the current + next two lines).

Both forms end up sending the same extracted range through the same prompt
composition, so pick whichever is more convenient at the time.

## Known limitations (v1)

`:ClaudeAssistantExplain` (and the other actions) are purely **text-based**:
they send the raw selected/motion-covered text plus your configured prompt
prefix. There is no LSP or tree-sitter based symbol resolution — the plugin
does not expand a selection to its enclosing function, resolve references,
or pull in type information. Richer symbol-aware context is a planned later
phase, not part of this version.
