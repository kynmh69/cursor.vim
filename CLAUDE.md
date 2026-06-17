# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**cursoragent.nvim** — a Neovim plugin (published as `kynmh69/cursor.vim`) that integrates the [Cursor Agent CLI](https://cursor.com) into Neovim. It is pure Lua, requires Neovim >= 0.10, and has no external Lua dependencies beyond Neovim's built-in APIs.

Runtime requirements: `agent` CLI in PATH, `CURSOR_API_KEY` environment variable.

## Running tests

Tests use the [Busted](https://lunarmodules.github.io/busted/) framework. The tests mock Neovim APIs so they run outside Neovim:

```bash
# Run all tests
busted tests/

# Run a single spec file
busted tests/cursoragent/config_spec.lua
```

Tests live in `tests/cursoragent/` and reset module state in `before_each` (e.g. `config.setup(nil)`, `jsonrpc.reset_buffer()`).

There is no build step — the plugin is loaded directly as Lua source by Neovim's runtime.

## Architecture

The plugin has **three operational modes**, selectable via `mode` config:

| Mode | Description |
|------|-------------|
| `acp` | Full bidirectional JSON-RPC 2.0 over stdio via `agent acp`. **Default and recommended.** |
| `terminal` | Interactive `agent` session in a Neovim split terminal. |
| `headless` | One-shot via `agent -p <prompt> --output-format json`. Used for `:CursorAgentReview`. |

### Module responsibilities

**`lua/cursoragent/init.lua`** — Public API. Holds the ACP client and session singletons (`_acp_client`, `_acp_session`). All user-facing functions (`setup`, `toggle`, `send_text`, `review`, etc.) route through here. `ensure_acp_ready(callback)` is the central lazy-start helper.

**`lua/cursoragent/acp/`** — ACP mode internals:
- `client.lua` — Spawns and manages the `agent acp` subprocess via `vim.system()`. Owns the I/O loop, framing, and request/response correlation.
- `jsonrpc.lua` — Stateless JSON-RPC 2.0 framing: `Content-Length` header framing with a newline-delimited fallback for partial reads. Has its own line buffer (`reset_buffer()` resets it).
- `session.lua` — State machine on top of the client. States: `IDLE → INITIALIZING → AUTHENTICATING → READY → PROMPTING ↔ WAITING_PERMISSION`. Handles `new_session`, `send_prompt`, `select_model`, `set_mode`.
- `permission.lua` — Floating window UI for permission requests (`ask` / `allow_edits` / `yolo` modes).

**`lua/cursoragent/terminal/`** — Terminal mode provider abstraction. `init.lua` auto-selects among `snacks.lua` (Snacks.nvim), `native.lua` (`vim.fn.termopen`), and `external.lua` (external emulator).

**`lua/cursoragent/config.lua`** — Singleton config with deep merge. Access values via `config.values.*` or dot-path `config.get("acp.permission.mode")`.

**`lua/cursoragent/context.lua`** — Accumulates `@file:path:start-end` reference strings sent alongside prompts.

**`lua/cursoragent/diff.lua`** — Diff UI for accepting/rejecting file change proposals from ACP mode.

**`lua/cursoragent/headless.lua`** — Wraps `agent -p` and parses the JSON event stream. Used by `:CursorAgentReview`.

**`plugin/cursoragent.lua`** — Neovim auto-load entry point. Guards double-load via `vim.g.loaded_cursoragent`. Calls `M.setup_defaults()` if `setup()` was not called explicitly.

### Key flow: ACP send

`M.send_text(text)` → `ensure_acp_ready(cb)` → `client:spawn()` → `session:start()` → `session:new_session()` → `session:send_prompt(text, context_str, handlers)` → streaming `on_update` events → file change proposals routed to `diff.show()`.

## Code conventions

- All modules use the `local M = {}; …; return M` pattern.
- Neovim APIs used: `vim.system()` (>= 0.10), `vim.api.*`, `vim.fn.*`, `vim.ui.select`, `vim.notify`, `vim.defer_fn`.
- Lua 5.1 compatible (Neovim's LuaJIT runtime). Avoid 5.2+ features (`goto`, `<const>`, `<close>`).
- Callbacks follow the `{ on_done = fn, on_error = fn, on_update = fn }` options-table pattern.
- Log via `require("cursoragent.logger")`, not `print()` or bare `vim.notify`.
