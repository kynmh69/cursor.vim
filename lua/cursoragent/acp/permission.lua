--- lua/cursoragent/acp/permission.lua
--- Permission UI for ACP session/request_permission events

local M = {}

local logger = require("cursoragent.logger")

--- Operation types that are considered "file edits" (auto-approved in allow_edits mode)
local FILE_EDIT_OPERATIONS = {
  write_file = true,
  edit_file = true,
  create_file = true,
  delete_file = true,
  rename_file = true,
  move_file = true,
}

--- Check if an operation is a file edit
---@param operation table permission request operation
---@return boolean
local function is_file_edit(operation)
  if not operation then
    return false
  end
  local op_type = operation.type or operation.operation or operation.action
  return FILE_EDIT_OPERATIONS[op_type] == true
end

--- Format a permission request for display
---@param req table permission request object from ACP
---@return string[] lines to display
local function format_request(req)
  local lines = {}

  table.insert(lines, "  Permission Request")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "")

  local operation = req.operation or req.params or req
  local op_type = operation.type or operation.operation or operation.action or "unknown"
  table.insert(lines, string.format("  Operation: %s", op_type))

  if operation.path or operation.file then
    table.insert(lines, string.format("  File: %s", operation.path or operation.file))
  end

  if operation.command or operation.cmd then
    table.insert(lines, string.format("  Command: %s", operation.command or operation.cmd))
  end

  if operation.description then
    table.insert(lines, string.format("  Description: %s", operation.description))
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "  [a] Allow  [A] Allow Always  [d] Deny")
  table.insert(lines, "")

  return lines
end

--- Show the permission floating window and handle user input.
---@param req table permission request from ACP
---@param approve_fn fun(req_id: any, always: boolean) callback to approve
---@param deny_fn fun(req_id: any) callback to deny
function M.show(req, approve_fn, deny_fn)
  local req_id = req.id or req.request_id

  -- Get lines to display
  local lines = format_request(req)

  -- Calculate window dimensions
  local width = 52
  local height = #lines + 1

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "cursoragent-permission")

  -- Position in the center of the screen
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " cursoragent ",
    title_pos = "center",
    focusable = true,
    zindex = 50,
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", false)

  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  -- Key mappings
  local map_opts = { noremap = true, silent = true, buffer = buf }

  -- Allow (once)
  vim.keymap.set("n", "a", function()
    close_win()
    if approve_fn then
      approve_fn(req_id, false)
    end
  end, map_opts)

  -- Allow Always
  vim.keymap.set("n", "A", function()
    close_win()
    if approve_fn then
      approve_fn(req_id, true)
    end
  end, map_opts)

  -- Deny
  vim.keymap.set("n", "d", function()
    close_win()
    if deny_fn then
      deny_fn(req_id)
    end
  end, map_opts)

  -- Escape also denies
  vim.keymap.set("n", "<Esc>", function()
    close_win()
    if deny_fn then
      deny_fn(req_id)
    end
  end, map_opts)

  -- q also denies
  vim.keymap.set("n", "q", function()
    close_win()
    if deny_fn then
      deny_fn(req_id)
    end
  end, map_opts)

  logger.debug("Permission window shown for request id=%s", tostring(req_id))
end

--- Handle a permission request according to the configured mode.
--- Depending on config, this may auto-approve, show UI, or auto-deny.
---@param req table permission request from ACP
---@param approve_fn fun(req_id: any, always: boolean) callback to approve
---@param deny_fn fun(req_id: any) callback to deny
---@param mode string "ask"|"allow_edits"|"yolo"
function M.handle(req, approve_fn, deny_fn, mode)
  mode = mode or "ask"

  if mode == "yolo" then
    -- Auto-approve everything
    logger.debug("yolo mode: auto-approving permission request")
    local req_id = req.id or req.request_id
    if approve_fn then
      vim.schedule(function()
        approve_fn(req_id, false)
      end)
    end
    return
  end

  if mode == "allow_edits" then
    local operation = req.operation or req.params or req
    if is_file_edit(operation) then
      -- Auto-approve file edits
      logger.debug("allow_edits mode: auto-approving file edit")
      local req_id = req.id or req.request_id
      if approve_fn then
        vim.schedule(function()
          approve_fn(req_id, false)
        end)
      end
      return
    end
    -- Fall through to ask for non-file-edit operations
  end

  -- "ask" mode (or allow_edits for non-file operations): show UI
  vim.schedule(function()
    M.show(req, approve_fn, deny_fn)
  end)
end

return M
