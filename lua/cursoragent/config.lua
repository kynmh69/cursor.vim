--- lua/cursoragent/config.lua
--- Default configuration and merge logic for cursoragent.nvim

local M = {}

--- Default configuration values
M.defaults = {
  agent_cmd = nil, -- defaults to "agent" at runtime
  mode = "acp", -- "acp" | "headless" | "terminal"
  api_key_env = "CURSOR_API_KEY",
  model = nil,
  auto_start = true,
  log_level = "info",
  acp = {
    auto_authenticate = true,
    permission = {
      mode = "ask", -- "ask" | "allow_edits" | "yolo"
    },
  },
  headless = {
    output_format = "json", -- "json" | "stream-json" | "text"
    force = false,
  },
  track_selection = true,
  visual_demotion_delay_ms = 50,
  terminal = {
    split_side = "right",
    split_width_percentage = 0.30,
    provider = "auto", -- "auto" | "snacks" | "native" | "external"
    git_repo_cwd = true,
  },
  diff_opts = { layout = "vertical", keep_terminal_focus = false },
}

--- Current active configuration (starts as a copy of defaults)
M.values = vim.deepcopy(M.defaults)

--- Valid mode values
local VALID_MODES = { acp = true, headless = true, terminal = true }

--- Valid permission modes
local VALID_PERMISSION_MODES = { ask = true, allow_edits = true, yolo = true }

--- Valid terminal providers
local VALID_PROVIDERS = { auto = true, snacks = true, native = true, external = true }

--- Valid output formats
local VALID_OUTPUT_FORMATS = { json = true, ["stream-json"] = true, text = true }

--- Deep merge table b into table a (a is mutated and returned)
--- Values in b override values in a. Tables are merged recursively.
---@param a table
---@param b table
---@return table
local function deep_merge(a, b)
  for k, v in pairs(b) do
    if type(v) == "table" and type(a[k]) == "table" then
      deep_merge(a[k], v)
    else
      a[k] = v
    end
  end
  return a
end

--- Validate configuration values and emit warnings for invalid ones
---@param cfg table
local function validate(cfg)
  if cfg.mode and not VALID_MODES[cfg.mode] then
    vim.notify(
      string.format(
        "[cursoragent] Invalid mode %q. Must be one of: acp, headless, terminal. Falling back to 'acp'.",
        cfg.mode
      ),
      vim.log.levels.WARN
    )
    cfg.mode = "acp"
  end

  if cfg.acp and cfg.acp.permission and cfg.acp.permission.mode then
    if not VALID_PERMISSION_MODES[cfg.acp.permission.mode] then
      vim.notify(
        string.format(
          "[cursoragent] Invalid acp.permission.mode %q. Must be one of: ask, allow_edits, yolo. Falling back to 'ask'.",
          cfg.acp.permission.mode
        ),
        vim.log.levels.WARN
      )
      cfg.acp.permission.mode = "ask"
    end
  end

  if cfg.terminal and cfg.terminal.provider then
    if not VALID_PROVIDERS[cfg.terminal.provider] then
      vim.notify(
        string.format(
          "[cursoragent] Invalid terminal.provider %q. Must be one of: auto, snacks, native, external. Falling back to 'auto'.",
          cfg.terminal.provider
        ),
        vim.log.levels.WARN
      )
      cfg.terminal.provider = "auto"
    end
  end

  if cfg.headless and cfg.headless.output_format then
    if not VALID_OUTPUT_FORMATS[cfg.headless.output_format] then
      vim.notify(
        string.format(
          "[cursoragent] Invalid headless.output_format %q. Must be one of: json, stream-json, text. Falling back to 'json'.",
          cfg.headless.output_format
        ),
        vim.log.levels.WARN
      )
      cfg.headless.output_format = "json"
    end
  end

  if cfg.terminal and cfg.terminal.split_width_percentage then
    local pct = cfg.terminal.split_width_percentage
    if type(pct) ~= "number" or pct <= 0 or pct >= 1 then
      vim.notify(
        "[cursoragent] terminal.split_width_percentage must be a number between 0 and 1 (exclusive). Falling back to 0.30.",
        vim.log.levels.WARN
      )
      cfg.terminal.split_width_percentage = 0.30
    end
  end
end

--- Setup configuration by merging user options into defaults
---@param opts table|nil user-provided options to merge
---@return table the resulting merged configuration
function M.setup(opts)
  -- Reset to defaults first
  M.values = vim.deepcopy(M.defaults)

  if opts and type(opts) == "table" then
    deep_merge(M.values, opts)
  end

  validate(M.values)
  return M.values
end

--- Get the effective agent command (falls back to "agent")
---@return string
function M.get_agent_cmd()
  return M.values.agent_cmd or "agent"
end

--- Get a nested config value by dot-separated path
---@param path string e.g. "acp.permission.mode"
---@return any
function M.get(path)
  local parts = vim.split(path, ".", { plain = true })
  local current = M.values
  for _, part in ipairs(parts) do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

return M
