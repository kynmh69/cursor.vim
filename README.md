# cursoragent.nvim

Neovim plugin for [Cursor Agent CLI](https://cursor.com) integration.

## Requirements

- Neovim >= 0.10
- `agent` CLI (install: `curl https://cursor.com/install -fsS | bash`)
- `CURSOR_API_KEY` environment variable

## Installation

### lazy.nvim

```lua
{
  "kynmh69/cursor.vim",
  dependencies = { "folke/snacks.nvim" }, -- optional, for better terminal
  opts = {},
}
```

### LazyVim (recommended keymaps)

```lua
return {
  "kynmh69/cursor.vim",
  dependencies = { "folke/snacks.nvim" },
  opts = { mode = "acp" },
  keys = {
    { "<leader>a",  nil,                                   desc = "AI/Cursor Agent" },
    { "<leader>ac", "<cmd>CursorAgent<cr>",                desc = "Toggle Cursor Agent" },
    { "<leader>af", "<cmd>CursorAgentFocus<cr>",           desc = "Focus Cursor Agent" },
    { "<leader>ab", "<cmd>CursorAgentAdd %<cr>",           desc = "Add current buffer" },
    { "<leader>am", "<cmd>CursorAgentSelectModel<cr>",     desc = "Select model" },
    { "<leader>ap", "<cmd>CursorAgentMode plan<cr>",       desc = "Plan mode" },
    { "<leader>ar", "<cmd>CursorAgentReview<cr>",          desc = "Review selection" },
    { "<leader>as", "<cmd>CursorAgentSend<cr>",  mode = "v", desc = "Send selection" },
    {
      "<leader>as", "<cmd>CursorAgentTreeAdd<cr>",         desc = "Add file",
      ft = { "neo-tree", "oil", "minifiles", "NvimTree", "netrw" },
    },
    { "<leader>aa", "<cmd>CursorAgentDiffAccept<cr>",      desc = "Accept diff" },
    { "<leader>ad", "<cmd>CursorAgentDiffDeny<cr>",        desc = "Deny diff" },
  },
}
```

## Configuration

```lua
require("cursoragent").setup({
  agent_cmd = nil,             -- CLI command (default: "agent")
  mode = "acp",                -- "acp" | "headless" | "terminal"
  api_key_env = "CURSOR_API_KEY",
  model = nil,                 -- nil = Auto; or "claude-opus-4", "gpt-4o", etc.
  auto_start = true,
  log_level = "info",          -- "debug" | "info" | "warn" | "error"

  acp = {
    auto_authenticate = true,
    permission = {
      mode = "ask",            -- "ask" | "allow_edits" | "yolo"
    },
  },

  headless = {
    output_format = "json",    -- "json" | "stream-json" | "text"
    force = false,
  },

  track_selection = true,
  visual_demotion_delay_ms = 50,

  terminal = {
    split_side = "right",
    split_width_percentage = 0.30,
    provider = "auto",         -- "auto" | "snacks" | "native" | "external"
    git_repo_cwd = true,
  },

  diff_opts = { layout = "vertical", keep_terminal_focus = false },
})
```

## Modes

| Mode | Description |
|------|-------------|
| `acp` | Full bidirectional protocol via `agent acp` (JSON-RPC 2.0 over stdio). Supports streaming responses, file change proposals, and permission requests. **Recommended.** |
| `headless` | One-shot non-interactive via `agent -p`. Best for quick reviews and scripted tasks. |
| `terminal` | Opens an interactive `agent` session in a split terminal. Simplest fallback. |

## Commands

| Command | Description |
|---------|-------------|
| `:CursorAgent` | Toggle the agent (mode-dependent) |
| `:CursorAgentFocus` | Focus the agent window |
| `:CursorAgentSend [text]` | Send visual selection or text to the agent |
| `:CursorAgentAdd <path> [start] [end]` | Add file or line range to context |
| `:CursorAgentTreeAdd` | Add file under cursor in neo-tree / oil / NvimTree |
| `:CursorAgentSelectModel` | Pick a model interactively |
| `:CursorAgentMode {plan\|ask\|agent}` | Switch agent mode |
| `:CursorAgentReview` | Run headless review on selection or current buffer |
| `:CursorAgentDiffAccept` | Accept and write a proposed diff |
| `:CursorAgentDiffDeny` | Reject a proposed diff |
| `:CursorAgentStatus` | Show session / context status |

## Permission modes

When the agent requests permission to perform an operation (edit file, run command, etc.):

| Mode | Behavior |
|------|----------|
| `ask` | Show a floating window with **[a] Allow**, **[A] Allow Always**, **[d] Deny** |
| `allow_edits` | Auto-approve file edits; ask for shell commands |
| `yolo` | Auto-approve everything |

## Context files

Add files to the agent's context with `:CursorAgentAdd`:

```
:CursorAgentAdd %                  " current buffer
:CursorAgentAdd src/foo.lua        " specific file
:CursorAgentAdd src/foo.lua 10 50  " lines 10-50
```

From a file tree, use `:CursorAgentTreeAdd` (works with neo-tree, oil.nvim, mini.files, NvimTree, netrw).

## Architecture

```
cursoragent.nvim/
├── plugin/cursoragent.lua          # entry point
└── lua/cursoragent/
    ├── init.lua                    # public API
    ├── config.lua                  # defaults & validation
    ├── commands.lua                # :CursorAgent* commands
    ├── selection.lua               # visual selection tracking
    ├── context.lua                 # @file reference accumulator
    ├── diff.lua                    # diff accept/deny UI
    ├── headless.lua                # agent -p wrapper
    ├── integrations.lua            # neo-tree / oil / etc.
    ├── cwd.lua                     # git root detection
    ├── logger.lua
    ├── acp/
    │   ├── client.lua              # vim.system subprocess manager
    │   ├── jsonrpc.lua             # JSON-RPC 2.0 framing
    │   ├── session.lua             # ACP session state machine
    │   └── permission.lua          # permission request UI
    └── terminal/
        ├── init.lua                # provider selector
        ├── snacks.lua              # Snacks.nvim provider
        ├── native.lua              # vim.fn.termopen() provider
        └── external.lua            # external emulator fallback
```

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for
development setup, how to run the tests, and the pull request workflow.

## License

Apache License 2.0
