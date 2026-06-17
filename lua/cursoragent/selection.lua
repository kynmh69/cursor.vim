--- lua/cursoragent/selection.lua
--- Tracks visual selection with demotion delay handling

local M = {}

--- Cached last visual selection
---@type table|nil
local last_selection = nil

--- Timer for visual demotion delay
---@type uv_timer_t|nil
local demotion_timer = nil

--- Get the current visual selection text and position info.
--- This must be called while still in visual mode or immediately after leaving it
--- (before the marks are overwritten).
---@return table|nil selection table with fields: text, start_line, end_line, bufnr, filepath
function M.get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Get visual marks - these persist after leaving visual mode
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- start_pos / end_pos format: {bufnum, lnum, col, off}
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line == 0 or end_line == 0 then
    return nil
  end

  -- Ensure start <= end
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  -- Get the actual lines (0-indexed for nvim_buf_get_lines)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if not lines or #lines == 0 then
    return nil
  end

  -- Trim first and last lines to the column selection
  -- end_col can be very large (2147483647) for visual line mode, meaning end of line
  local max_col = 2147483647
  if #lines == 1 then
    local line = lines[1]
    local s = math.max(1, start_col)
    local e = end_col >= max_col and #line or math.min(end_col, #line)
    lines[1] = line:sub(s, e)
  else
    -- Trim first line from start_col
    lines[1] = lines[1]:sub(math.max(1, start_col))
    -- Trim last line to end_col
    local last = lines[#lines]
    if end_col < max_col then
      lines[#lines] = last:sub(1, math.min(end_col, #last))
    end
  end

  local text = table.concat(lines, "\n")

  return {
    text = text,
    start_line = start_line,
    end_line = end_line,
    bufnr = bufnr,
    filepath = filepath,
  }
end

--- Get the last cached visual selection.
--- This is saved with a small delay to handle the "visual demotion" case
--- where Neovim clears the selection before the command runs.
---@return table|nil last selection or nil
function M.get_last_selection()
  return last_selection
end

--- Save the current visual selection to the cache.
--- Called from autocmd on ModeChanged (leaving visual mode).
function M.save_selection()
  local sel = M.get_visual_selection()
  if sel then
    last_selection = sel
  end
end

--- Setup autocmds to track visual selection with demotion delay.
--- The delay (from config.visual_demotion_delay_ms) gives time for marks to settle.
function M.setup()
  local ok, config = pcall(require, "cursoragent.config")
  local delay_ms = (ok and config.values and config.values.visual_demotion_delay_ms) or 50

  local group = vim.api.nvim_create_augroup("CursorAgentSelection", { clear = true })

  -- When leaving visual mode, save the selection after a short delay
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[vV\x16]*:*", -- leaving any visual mode
    callback = function()
      -- Cancel any pending timer
      if demotion_timer then
        demotion_timer:stop()
        demotion_timer:close()
        demotion_timer = nil
      end

      -- Use a short delay to allow marks to be set properly
      if delay_ms > 0 then
        demotion_timer = vim.loop.new_timer()
        demotion_timer:start(
          delay_ms,
          0,
          vim.schedule_wrap(function()
            M.save_selection()
            if demotion_timer then
              demotion_timer:close()
              demotion_timer = nil
            end
          end)
        )
      else
        vim.schedule(function()
          M.save_selection()
        end)
      end
    end,
  })
end

--- Get the text of a selection as a formatted string with line range info.
---@param sel table|nil selection table (from get_visual_selection or get_last_selection)
---@return string formatted selection text or empty string
function M.format_selection(sel)
  if not sel then
    return ""
  end

  local header = ""
  if sel.filepath and sel.filepath ~= "" then
    header = string.format("File: %s (lines %d-%d)\n", sel.filepath, sel.start_line, sel.end_line)
  else
    header = string.format("(lines %d-%d)\n", sel.start_line, sel.end_line)
  end

  return header .. sel.text
end

return M
