--- lua/cursoragent/context.lua
--- Builds @file references for Cursor context

local M = {}

--- List of accumulated context items
---@type table[]
local context_items = {}

--- Add a file reference to the context.
--- Returns the @file reference string that was added.
---@param path string file path
---@param start_line number|nil optional start line for range reference
---@param end_line number|nil optional end line for range reference
---@return string the @file reference string
function M.add_file(path, start_line, end_line)
  -- Normalize the path
  local normalized = vim.fn.fnamemodify(path, ":p")

  local ref
  if start_line and end_line then
    ref = string.format("@file:%s:%d-%d", normalized, start_line, end_line)
  elseif start_line then
    ref = string.format("@file:%s:%d", normalized, start_line)
  else
    ref = string.format("@file:%s", normalized)
  end

  -- Check for duplicates before adding
  for _, item in ipairs(context_items) do
    if item.ref == ref then
      return ref
    end
  end

  table.insert(context_items, {
    path = normalized,
    start_line = start_line,
    end_line = end_line,
    ref = ref,
  })

  return ref
end

--- Add a file reference from a Neovim buffer.
---@param bufnr number|nil buffer number (defaults to current buffer)
---@param start_line number|nil optional start line
---@param end_line number|nil optional end line
---@return string|nil the @file reference string, or nil if buffer has no associated file
function M.add_buffer(bufnr, start_line, end_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return nil
  end
  return M.add_file(filepath, start_line, end_line)
end

--- Get all context as a single string with each @file reference on its own line.
---@return string
function M.get_context_string()
  local parts = {}
  for _, item in ipairs(context_items) do
    table.insert(parts, item.ref)
  end
  return table.concat(parts, "\n")
end

--- Clear all accumulated context items.
function M.clear()
  context_items = {}
end

--- Return a copy of the list of context items.
---@return table[]
function M.list()
  return vim.deepcopy(context_items)
end

--- Get the count of context items.
---@return number
function M.count()
  return #context_items
end

--- Remove a specific file reference from context.
---@param path string file path to remove
---@return boolean true if removed, false if not found
function M.remove_file(path)
  local normalized = vim.fn.fnamemodify(path, ":p")
  for i, item in ipairs(context_items) do
    if item.path == normalized then
      table.remove(context_items, i)
      return true
    end
  end
  return false
end

--- Format context items as a human-readable summary string.
---@return string
function M.format_summary()
  if #context_items == 0 then
    return "(no context files)"
  end

  local lines = {}
  for i, item in ipairs(context_items) do
    local display = vim.fn.fnamemodify(item.path, ":~")
    if item.start_line and item.end_line then
      display = display .. string.format(" [%d-%d]", item.start_line, item.end_line)
    elseif item.start_line then
      display = display .. string.format(" [%d]", item.start_line)
    end
    table.insert(lines, string.format("%d. %s", i, display))
  end
  return table.concat(lines, "\n")
end

return M
