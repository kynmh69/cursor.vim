--- lua/cursoragent/cwd.lua
--- Working directory resolution with optional git root detection

local M = {}

--- Get the effective working directory.
--- If config.terminal.git_repo_cwd is true, tries to find the git repository root.
--- Falls back to vim.fn.getcwd() if git is unavailable or not in a repo.
---@return string the working directory path
function M.get()
  local ok, config = pcall(require, "cursoragent.config")
  local use_git = ok and config.values and config.values.terminal and config.values.terminal.git_repo_cwd

  if use_git then
    local result = vim.fn.systemlist("git rev-parse --show-toplevel")
    -- vim.fn.systemlist returns an empty table or the git root on success
    -- vim.v.shell_error is 0 on success
    if vim.v.shell_error == 0 and result and result[1] and result[1] ~= "" then
      return result[1]
    end
  end

  return vim.fn.getcwd()
end

--- Get the git root for a specific path, or nil if not in a git repo
---@param path string|nil path to check (defaults to cwd)
---@return string|nil git root path or nil
function M.get_git_root(path)
  local cmd = "git rev-parse --show-toplevel"
  if path then
    cmd = string.format("git -C %s rev-parse --show-toplevel", vim.fn.shellescape(path))
  end

  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error == 0 and result and result[1] and result[1] ~= "" then
    return result[1]
  end
  return nil
end

--- Check if a path is inside a git repository
---@param path string|nil path to check (defaults to cwd)
---@return boolean
function M.is_git_repo(path)
  return M.get_git_root(path) ~= nil
end

return M
