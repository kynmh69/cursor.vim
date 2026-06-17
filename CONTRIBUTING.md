# Contributing to cursoragent.nvim

Thanks for your interest in contributing! `cursoragent.nvim` (published as
`kynmh69/cursor.vim`) is a pure-Lua Neovim plugin that integrates the
[Cursor Agent CLI](https://cursor.com) into Neovim. This guide explains how to
set up your environment, make changes, and submit them.

## Table of contents

- [Code of conduct](#code-of-conduct)
- [Ways to contribute](#ways-to-contribute)
- [Development setup](#development-setup)
- [Running tests](#running-tests)
- [Code conventions](#code-conventions)
- [Project structure](#project-structure)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Reporting bugs](#reporting-bugs)
- [Requesting features](#requesting-features)

## Code of conduct

Be respectful and constructive. We want this project to be a welcoming place
for contributors of all backgrounds and experience levels.

## Ways to contribute

- **Report bugs** by opening an issue with reproduction steps.
- **Suggest features** or improvements via an issue.
- **Improve documentation** — the README, this guide, or in-code comments.
- **Fix bugs or add features** by opening a pull request.
- **Add tests** — coverage is currently focused on a few modules and more is
  always welcome.

## Development setup

Requirements:

- Neovim >= 0.10
- The `agent` CLI in your `PATH` (install: `curl https://cursor.com/install -fsS | bash`)
- The `CURSOR_API_KEY` environment variable (only needed to run the plugin
  against a live agent — not required for tests)
- [Busted](https://lunarmodules.github.io/busted/) for running the test suite
  (install via LuaRocks: `luarocks install busted`)

There is **no build step**. The plugin is loaded directly as Lua source by
Neovim's runtime, so you can iterate by editing files under `lua/` and
reloading Neovim.

To try your changes locally, point your plugin manager at your local checkout.
For example, with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = "~/path/to/cursor.vim",
  opts = {},
}
```

## Running tests

Tests use the [Busted](https://lunarmodules.github.io/busted/) framework and
mock Neovim APIs so they run outside of Neovim:

```bash
# Run all tests
busted tests/

# Run a single spec file
busted tests/cursoragent/config_spec.lua
```

Specs live in `tests/cursoragent/`. Reset module state in `before_each`
(for example `config.setup(nil)` or `jsonrpc.reset_buffer()`) so tests do not
leak state between cases. Please add or update tests for any behavior you
change, and make sure the full suite passes before opening a pull request.

## Code conventions

This project targets Neovim's LuaJIT runtime (Lua 5.1). Follow the existing
style:

- All modules use the `local M = {}; …; return M` pattern.
- Stay **Lua 5.1 compatible**. Avoid 5.2+ features such as `goto`, `<const>`,
  and `<close>`.
- Use Neovim APIs already in use across the codebase: `vim.system()` (>= 0.10),
  `vim.api.*`, `vim.fn.*`, `vim.ui.select`, `vim.notify`, `vim.defer_fn`.
- Callbacks follow the options-table pattern:
  `{ on_done = fn, on_error = fn, on_update = fn }`.
- Log through `require("cursoragent.logger")` — do not use `print()` or bare
  `vim.notify`.
- Access configuration via `config.values.*` or the dot-path helper
  `config.get("acp.permission.mode")`.

For a deeper explanation of the architecture and the three operational modes
(`acp`, `terminal`, `headless`), see [`CLAUDE.md`](./CLAUDE.md).

## Project structure

```
cursoragent.nvim/
├── plugin/cursoragent.lua          # entry point
├── lua/cursoragent/
│   ├── init.lua                    # public API
│   ├── config.lua                  # defaults & validation
│   ├── commands.lua                # :CursorAgent* commands
│   ├── acp/                        # JSON-RPC ACP mode internals
│   └── terminal/                   # terminal provider abstraction
└── tests/cursoragent/              # Busted specs
```

See the README and `CLAUDE.md` for the full module breakdown.

## Commit messages

Use clear, descriptive commit messages. This repository follows the
[Conventional Commits](https://www.conventionalcommits.org/) style already
present in the history, for example:

```
feat: add streaming support to headless mode
fix: handle partial reads in jsonrpc framing
docs: clarify permission modes in README
test: add coverage for config deep merge
```

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.

## Pull requests

1. Fork the repository and create a topic branch from `main`.
2. Make your change, keeping commits focused and logically grouped.
3. Add or update tests, and run `busted tests/` to confirm everything passes.
4. Update the README or other docs if your change affects user-facing behavior.
5. Open a pull request describing **what** changed and **why**. Link any
   related issues.

Keep pull requests as small and focused as practical — it makes review faster
and easier.

## Reporting bugs

When filing a bug report, please include:

- Your Neovim version (`nvim --version`)
- The `agent` CLI version, if relevant
- The plugin `mode` you are using (`acp`, `terminal`, or `headless`)
- Steps to reproduce, expected behavior, and actual behavior
- Relevant log output (set `log_level = "debug"` for more detail)

## Requesting features

Open an issue describing the use case and the problem you are trying to solve.
Concrete examples of how you would use the feature help a lot in evaluating it.

---

Thanks again for contributing! 🎉
