--- lua/cursoragent/logger.lua
--- Simple logger with configurable levels using vim.notify

local M = {}

--- Numeric log levels (higher = more severe)
local LEVELS = {
  debug = 1,
  info = 2,
  warn = 3,
  error = 4,
}

--- Map our level names to vim.log.levels
local VIM_LEVELS = {
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

--- Get current minimum log level from config
---@return number
local function get_min_level()
  local ok, config = pcall(require, "cursoragent.config")
  if not ok then
    return LEVELS.info
  end
  local level_name = config.values and config.values.log_level or "info"
  return LEVELS[level_name] or LEVELS.info
end

--- Log a message at the given level
---@param level string "debug"|"info"|"warn"|"error"
---@param msg string message to log
---@param ... any additional format arguments
local function log(level, msg, ...)
  local min_level = get_min_level()
  local this_level = LEVELS[level] or LEVELS.info

  if this_level < min_level then
    return
  end

  local formatted
  if select("#", ...) > 0 then
    local ok, result = pcall(string.format, msg, ...)
    if ok then
      formatted = result
    else
      formatted = msg .. " " .. table.concat({ ... }, " ")
    end
  else
    formatted = tostring(msg)
  end

  local vim_level = VIM_LEVELS[level] or vim.log.levels.INFO
  vim.notify("[cursoragent] " .. formatted, vim_level)
end

--- Log at debug level
---@param msg string
---@param ... any
function M.debug(msg, ...)
  log("debug", msg, ...)
end

--- Log at info level
---@param msg string
---@param ... any
function M.info(msg, ...)
  log("info", msg, ...)
end

--- Log at warn level
---@param msg string
---@param ... any
function M.warn(msg, ...)
  log("warn", msg, ...)
end

--- Log at error level
---@param msg string
---@param ... any
function M.error(msg, ...)
  log("error", msg, ...)
end

--- Check if a level would be logged
---@param level string
---@return boolean
function M.is_enabled(level)
  local min_level = get_min_level()
  local this_level = LEVELS[level] or LEVELS.info
  return this_level >= min_level
end

return M
