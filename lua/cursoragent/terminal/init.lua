--- lua/cursoragent/terminal/init.lua
--- Terminal provider selector - dispatches to snacks, native, or external

local M = {}

local logger = require("cursoragent.logger")

--- Resolve the active provider module based on config.
---@return table provider module
local function get_provider()
  local config = require("cursoragent.config")
  local pref = config.values.terminal.provider or "auto"

  if pref == "snacks" then
    local snacks = require("cursoragent.terminal.snacks")
    if snacks.is_available() then
      return snacks
    end
    logger.warn("snacks provider requested but Snacks.nvim not available, falling back to native")
    return require("cursoragent.terminal.native")
  elseif pref == "native" then
    return require("cursoragent.terminal.native")
  elseif pref == "external" then
    return require("cursoragent.terminal.external")
  else
    -- auto: prefer snacks > native > external
    local snacks = require("cursoragent.terminal.snacks")
    if snacks.is_available() then
      return snacks
    end
    return require("cursoragent.terminal.native")
  end
end

--- Build the agent command array.
---@return string[]
local function build_cmd()
  local config = require("cursoragent.config")
  local cwd_mod = require("cursoragent.cwd")
  local agent_cmd = config.get_agent_cmd()
  local cmd = { agent_cmd }
  if config.values.model then
    vim.list_extend(cmd, { "--model", config.values.model })
  end
  -- cwd is handled via the terminal's working directory, not a flag
  _ = cwd_mod.get() -- ensure cwd is resolved (side-effect: sets process cwd)
  return cmd
end

--- Get terminal opts from config.
---@return table
local function terminal_opts()
  local config = require("cursoragent.config")
  return {
    split_side = config.values.terminal.split_side or "right",
    split_width_percentage = config.values.terminal.split_width_percentage or 0.30,
  }
end

--- Open the terminal (or show it if already open).
function M.open()
  local provider = get_provider()
  local cmd = build_cmd()
  local opts = terminal_opts()
  logger.debug("Opening terminal with provider: %s", tostring(provider))
  provider.open(cmd, opts)
end

--- Toggle terminal visibility.
function M.toggle()
  local provider = get_provider()
  local cmd = build_cmd()
  local opts = terminal_opts()
  provider.toggle(cmd, opts)
end

--- Focus the terminal window.
function M.focus()
  local provider = get_provider()
  if provider.focus then
    provider.focus()
  end
end

--- Check if terminal is currently open.
---@return boolean
function M.is_open()
  local provider = get_provider()
  if provider.is_open then
    return provider.is_open()
  end
  return false
end

--- Send text to the terminal.
---@param text string
function M.send_text(text)
  local provider = get_provider()
  if provider.send_text then
    provider.send_text(text)
  else
    logger.warn("Current terminal provider does not support send_text")
  end
end

return M
