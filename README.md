# claude-assistant.nvim

A vibecoded nvim plugin to go from vibe-coding to LLM-assisted coding.

I love vim, and recently I've been doing nothing but vibe-coding. I want to go back to
actually writing code, but with the convenience that Claude Code gives you, without ever
having to leave vim (and hopefully, without really having to type anything into the Claude
Code prompt).

The aspiration is having a Claude Code instance that acts more like a pair programmer
assisting you, rather than someone that writes all the code and leaves you the boring task
of reviewing it. No more Stack Overflow lookups, fewer bugs discovered at PR review time,
more understanding of your own code, and most importantly, more time spent *inside vim*.

It's built on top of [coder/claudecode.nvim](https://github.com/coder/claudecode.nvim),
which does the actual transport (the Claude Code terminal, and sending things to it). This
plugin is the thin layer on top: it turns a selection or a motion into a composed prompt and
keeps Claude in an assistant role. You stay the one writing the code — nothing here ever
touches your buffers.

## Status

Phase 1 is done and daily-usable. Select some code (or hit an operator + a motion) and send
it to Claude as a *review* or *explain* prompt, or just *paste* it into the prompt to ask
your own question around it. Everything past that is planned — see [Roadmap](#roadmap).

## Requirements

- [coder/claudecode.nvim](https://github.com/coder/claudecode.nvim) — the transport layer.
  There is no functionality without it.
- Neovim >= 0.10 (it uses `vim.fn.getregion()` to pull out visual/motion ranges).
- claudecode's terminal provider set to `native` or `snacks`. Sending is inert on the
  `external` and `none` providers, since Claude runs outside nvim there and there's no pane
  to write into.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "NaabZer/claude-assistant.nvim",
  dependencies = { "coder/claudecode.nvim" },
  opts = {},
}
```

`opts = {}` (or an explicit `require("claude-assistant").setup({})`) is required — that's
what registers the `:ClaudeAssistant*` commands and the `<Plug>` mappings. Without it the
plugin does nothing.

## Usage

Three actions. Each one works two ways: from a **visual selection**, or as a normal-mode
**operator + motion / text-object** (hit the mapping, then supply a motion like `ip` or `2j`).

| Command | What it does |
| --- | --- |
| `:ClaudeAssistantReview` | Sends the selection as a "review this for bugs and logic flaws" prompt, submitted. |
| `:ClaudeAssistantExplain` | Sends it as an "explain this and give usage examples" prompt, submitted. |
| `:ClaudeAssistantPaste` | Drops the selection into the prompt **without** submitting, and focuses the pane so you can ask your own thing. |
| `:ClaudeAssistantExplainFile` | Sends an "explain this and give usage examples" prompt plus a whole-file `@`-mention of the current buffer, submitted. Normal mode only — no selection involved. |

Default keybinds are off. Either map the `<Plug>` mappings yourself (in normal and visual
mode)...

```lua
vim.keymap.set({ "n", "x" }, "<leader>cr", "<Plug>(ClaudeAssistantReview)")
vim.keymap.set({ "n", "x" }, "<leader>ce", "<Plug>(ClaudeAssistantExplain)")
vim.keymap.set({ "n", "x" }, "<leader>cp", "<Plug>(ClaudeAssistantPaste)")
vim.keymap.set("n", "<leader>cE", "<Plug>(ClaudeAssistantExplainFile)")
```

...or set `keymaps.enable = true` to get those defaults installed for you.

### Insert-mode quick-send

Hit `<C-s>` while typing in insert mode and the current line is sent to Claude as-is
(no prompt prefix, no wrapping, no file reference) and submitted; the line is then
cleared and you stay in insert mode, ready to type the next one. Handy as a scratch
prompt line inside whatever file you're already in.

The clear only happens once the send is *confirmed* to have reached an already-open
Claude pane. If the pane was still starting up (cold start) or the send failed, the
line is left untouched and a `[claude-assistant] Sent - Claude pane was starting,
text kept.` notification is shown instead — your text is never silently lost. An
empty line does nothing.

This mapping is opt-in, same as the others: it's only installed (in insert mode) when
`keymaps.enable = true`, using the `keymaps.quicksend_insert` key (default `<C-s>`).

```lua
vim.keymap.set("i", "<C-s>", function() require("claude-assistant.send").send_line_insert() end)
```

> [!WARNING]
> Many terminals map `<C-s>` to XOFF (software flow control), which freezes the
> terminal on first use instead of triggering the mapping — `<C-q>` (XON) unfreezes
> it. Fix it one of three ways: run `stty -ixon` (e.g. in your shell rc) to disable
> flow control, use Neovim's built-in `<C-g>s` insert-mode literal-send fallback,
> or remap `keymaps.quicksend_insert` to a different key.

### What actually gets sent

It depends on the *kind* of selection, so Claude gets the most useful context:

- **Whole-line selection** (linewise visual, or an operator + a linewise motion like `ip`) →
  just a file reference, e.g. `@lua/config/keymaps.lua#L54-58`. Claude Code expands the
  `@`-mention and reads those exact lines itself (so it can see the surrounding code too).
- **Partial (charwise) selection** → the selected text wrapped as code (inline backticks for
  one line, a fenced block for several), followed by the reference in parens, e.g.
  `` `vim.keymap.set` ( @keymaps.lua#L54 ) `` — so Claude gets the exact fragment *and* where
  it's from.
- **Unnamed buffer** (nothing to reference) → just the wrapped text.

## Configuration

Defaults:

```lua
require("claude-assistant").setup({
  prompts = {
    review = "Review this for bugs and logic flaws:",
    explain = "Explain this and give usage examples:",
    explain_file = nil,       -- nil => falls back to prompts.explain
  },
  keymaps = {
    enable = false,            -- install the default <leader>c{r,e,p,E} maps
    review = "<leader>cr",
    explain = "<leader>ce",
    paste = "<leader>cp",
    explain_file = "<leader>cE",
    quicksend_insert = "<C-s>", -- insert-mode: send current line, clear it, stay in insert
  },
  reference = {
    linewise = "@%s#L%s",      -- whole-line selection: sent bare (path, lines)
    charwise = "( @%s#L%s )",  -- partial selection: appended after the code (path, lines)
  },
  role_prompt = nil,           -- nil => built-in default assistant role
  manage_claudecode = false,   -- let this plugin call claudecode.setup() for you
  claudecode = {},             -- passthrough opts, merged when manage_claudecode = true
})
```

Change `prompts.review` / `prompts.explain` to reword the instruction prefixes. The spaces
inside `reference.charwise`'s parens matter — a tight `(@file#L1)` isn't expanded by Claude
Code, but `( @file#L1 )` is.

`prompts.explain_file` lets you use a different wording for `:ClaudeAssistantExplainFile`
than for the selection-based `explain` — leave it `nil` to just reuse `prompts.explain`.
`keymaps.explain_file` is its opt-in default keybind, mapped in normal mode only (there's no
selection to act on, so no visual-mode mapping).

## Assistant role

The "review and explain, don't drive my code" role is injected with
`claude --append-system-prompt <role>`, baked into the command claudecode uses to launch
Claude. This is enforced per-launch at the process level, so it can't be quietly ignored
mid-session the way a skill or `CLAUDE.md` could.

Two ways to wire it:

```lua
-- (a) let the plugin own claudecode's setup
require("claude-assistant").setup({
  manage_claudecode = true,
  claudecode = { terminal = { provider = "native" } },
  role_prompt = "You are a strict, terse code reviewer.",  -- optional override
})

-- (b) or compose the terminal_cmd yourself
require("claudecode").setup({
  terminal_cmd = require("claude-assistant.role").terminal_cmd(),
  terminal = { provider = "native" },
})
```

## Roadmap

Rough plan, in the order I actually care about them. Phase 1 is done; the rest is where I'm
headed.

- **Phase 2 — Memory.** An evolving, per-repo/per-worktree memory the assistant reads at the
  start of every session: what I was mid-way through, decisions I made, things I keep getting
  stuck on. Captured mechanically via hooks, distilled on demand. Honestly also a pilot for a
  bigger idea — a development-specific LLM memory, a sort of Karpathy-style LLM wiki for how
  *you* work.
- **Phase 3 — Ergonomics.** Nicer keybinds for jumping in/out of the Claude pane and copying
  responses back out.
- **Phase 4 — Smarter explain.** Use LSP / tree-sitter to resolve the symbol under the cursor
  to its package/source and feed real docs and examples into the explain prompt, instead of
  just the raw text.
- **Phase 5 — Inline send. Done, out of order** — it turned out to be the easiest one. See
  [Insert-mode quick-send](#insert-mode-quick-send) above.

No wiki or `:help` pages yet — maybe later, if the thing proves itself.
