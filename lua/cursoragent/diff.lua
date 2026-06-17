--- lua/cursoragent/diff.lua
--- Shows diff proposals from ACP session/update events

local M = {}

local logger = require("cursoragent.logger")

-- Pending diff state
local pending = {
  filepath = nil,
  original = nil,
  proposed = nil,
  original_buf = nil,
  proposed_buf = nil,
  original_win = nil,
  proposed_win = nil,
}

--- Close any open diff windows and clean up.
local function close_diff()
  for _, key in ipairs({ "original_win", "proposed_win" }) do
    local win = pending[key]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    pending[key] = nil
  end
  for _, key in ipairs({ "original_buf", "proposed_buf" }) do
    local buf = pending[key]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    pending[key] = nil
  end
  pending.filepath = nil
  pending.original = nil
  pending.proposed = nil
end

--- Show a diff between original and proposed content.
---@param original string original file content
---@param proposed string proposed content
---@param filepath string the file path this diff applies to
---@param opts table|nil { layout? } layout: "vertical"|"horizontal"
function M.show(original, proposed, filepath, opts)
  opts = opts or {}
  close_diff()

  pending.filepath = filepath
  pending.original = original
  pending.proposed = proposed

  local layout = opts.layout or require("cursoragent.config").values.diff_opts.layout or "vertical"

  -- Create original buffer
  pending.original_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(pending.original_buf, 0, -1, false, vim.split(original, "\n"))
  vim.bo[pending.original_buf].buftype = "nofile"
  vim.bo[pending.original_buf].filetype = vim.filetype.match({ filename = filepath }) or ""
  vim.api.nvim_buf_set_name(pending.original_buf, "cursoragent://original/" .. vim.fn.fnamemodify(filepath, ":t"))

  -- Create proposed buffer
  pending.proposed_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(pending.proposed_buf, 0, -1, false, vim.split(proposed, "\n"))
  vim.bo[pending.proposed_buf].buftype = "nofile"
  vim.bo[pending.proposed_buf].filetype = vim.filetype.match({ filename = filepath }) or ""
  vim.api.nvim_buf_set_name(pending.proposed_buf, "cursoragent://proposed/" .. vim.fn.fnamemodify(filepath, ":t"))

  -- Open windows
  if layout == "horizontal" then
    vim.cmd("split")
    pending.original_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(pending.original_win, pending.original_buf)
    vim.cmd("split")
    pending.proposed_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(pending.proposed_win, pending.proposed_buf)
  else
    vim.cmd("vsplit")
    pending.original_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(pending.original_win, pending.original_buf)
    vim.cmd("vsplit")
    pending.proposed_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(pending.proposed_win, pending.proposed_buf)
  end

  -- Enable diff mode on both windows
  vim.api.nvim_set_current_win(pending.original_win)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(pending.proposed_win)
  vim.cmd("diffthis")

  -- Add title-like status to both buffers
  vim.api.nvim_buf_set_var(pending.original_buf, "cursoragent_diff_role", "original")
  vim.api.nvim_buf_set_var(pending.proposed_buf, "cursoragent_diff_role", "proposed")

  -- Keymaps in proposed buffer for accept/deny
  local map_opts = { noremap = true, silent = true, buffer = pending.proposed_buf }
  vim.keymap.set("n", "<leader>aa", function()
    M.accept(filepath)
  end, vim.tbl_extend("force", map_opts, { desc = "Accept diff" }))
  vim.keymap.set("n", "<leader>ad", function()
    M.deny()
  end, vim.tbl_extend("force", map_opts, { desc = "Deny diff" }))
  vim.keymap.set("n", "q", function()
    M.deny()
  end, map_opts)

  vim.notify(
    "[cursoragent] Diff ready. <leader>aa to accept, <leader>ad / q to deny.",
    vim.log.levels.INFO
  )
  logger.debug("Diff shown for %s", filepath)
end

--- Accept the proposed diff: write proposed content to file and close diff.
---@param filepath string|nil overrides pending.filepath if provided
function M.accept(filepath)
  filepath = filepath or pending.filepath
  if not filepath then
    logger.warn("No pending diff to accept")
    return
  end

  local content = pending.proposed
  if not content then
    logger.warn("No proposed content to write")
    return
  end

  -- Write to disk
  local ok, err = pcall(function()
    vim.fn.writefile(vim.split(content, "\n"), filepath)
  end)

  if not ok then
    logger.error("Failed to write file %s: %s", filepath, tostring(err))
    vim.notify("[cursoragent] Failed to write " .. filepath, vim.log.levels.ERROR)
    return
  end

  -- Reload the file in any existing buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == filepath or name == vim.fn.fnamemodify(filepath, ":p") then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit!")
        end)
        break
      end
    end
  end

  close_diff()
  vim.notify("[cursoragent] Changes accepted and written to " .. vim.fn.fnamemodify(filepath, ":~:."), vim.log.levels.INFO)
  logger.info("Accepted diff for %s", filepath)
end

--- Deny the proposed diff: close diff without writing.
function M.deny()
  local filepath = pending.filepath
  close_diff()
  vim.notify("[cursoragent] Diff denied.", vim.log.levels.INFO)
  if filepath then
    logger.debug("Denied diff for %s", filepath)
  end
end

--- Check if there is a pending diff.
---@return boolean
function M.has_pending()
  return pending.filepath ~= nil
end

--- Get a summary of the pending diff.
---@return table|nil { filepath, original_lines, proposed_lines }
function M.get_pending_info()
  if not pending.filepath then
    return nil
  end
  return {
    filepath = pending.filepath,
    original_lines = pending.original and select(2, pending.original:gsub("\n", "")) + 1 or 0,
    proposed_lines = pending.proposed and select(2, pending.proposed:gsub("\n", "")) + 1 or 0,
  }
end

return M
