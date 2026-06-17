--- lua/cursoragent/integrations.lua
--- File tree and plugin integrations for getting the file under cursor

local M = {}

local logger = require("cursoragent.logger")

--- Detect the current file tree filetype.
---@return string|nil filetype name
local function detect_filetree_ft()
  local ft = vim.bo.filetype
  local supported = {
    ["neo-tree"] = true,
    ["NvimTree"] = true,
    ["oil"] = true,
    ["minifiles"] = true,
    ["netrw"] = true,
  }
  return supported[ft] and ft or nil
end

--- Get path from neo-tree.
---@return string|nil
local function from_neo_tree()
  local ok, state = pcall(function()
    local mgr = require("neo-tree.sources.manager")
    local src = mgr.get_state("filesystem")
    return src and src.tree and src.tree:get_node()
  end)
  if not ok or not state then
    return nil
  end
  return state.path
end

--- Get path from NvimTree.
---@return string|nil
local function from_nvim_tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    return nil
  end
  local node = api.tree.get_node_under_cursor()
  return node and node.absolute_path
end

--- Get path from oil.nvim.
---@return string|nil
local function from_oil()
  local ok, oil = pcall(require, "oil")
  if not ok then
    return nil
  end
  local entry = oil.get_cursor_entry()
  if not entry then
    return nil
  end
  local dir = oil.get_current_dir()
  return dir and (dir .. entry.name) or nil
end

--- Get path from mini.files.
---@return string|nil
local function from_mini_files()
  local ok, mf = pcall(require, "mini.files")
  if not ok then
    return nil
  end
  local entry = mf.get_fs_entry()
  return entry and entry.path
end

--- Get path from netrw.
---@return string|nil
local function from_netrw()
  -- netrw stores current file in b:netrw_curdir + cursor line
  local curdir = vim.b.netrw_curdir
  if not curdir then
    return nil
  end
  local line = vim.fn.getline(".")
  -- Strip leading markers netrw adds
  local name = line:match("^%s*(.-)%s*$")
  if name and name ~= "" then
    return curdir .. "/" .. name
  end
  return nil
end

--- Get the file path under cursor in the active file tree.
---@return string|nil
function M.get_current_file()
  local ft = detect_filetree_ft()
  if not ft then
    -- Not in a file tree; return current buffer's file
    local path = vim.api.nvim_buf_get_name(0)
    return path ~= "" and path or nil
  end

  local getters = {
    ["neo-tree"] = from_neo_tree,
    ["NvimTree"] = from_nvim_tree,
    ["oil"] = from_oil,
    ["minifiles"] = from_mini_files,
    ["netrw"] = from_netrw,
  }

  local getter = getters[ft]
  if getter then
    local path = getter()
    if path then
      return path
    end
  end

  logger.warn("Could not get file path from %s", ft)
  return nil
end

--- Add the file under cursor to cursoragent context.
---@param start_line integer|nil optional start line
---@param end_line integer|nil optional end line
function M.add_current_to_context()
  local path = M.get_current_file()
  if not path then
    vim.notify("[cursoragent] No file found under cursor", vim.log.levels.WARN)
    return
  end

  local context = require("cursoragent.context")
  context.add_file(path)
  vim.notify("[cursoragent] Added to context: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
end

return M
