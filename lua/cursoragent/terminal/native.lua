--- lua/cursoragent/terminal/native.lua
--- Pure Neovim terminal fallback using termopen()

local M = {}

-- State tracking
local state = {
  buf = nil,
  win = nil,
  job_id = nil,
}

--- Check if the tracked buffer/window are still valid.
---@return boolean
local function is_valid()
  return state.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.win ~= nil
    and vim.api.nvim_win_is_valid(state.win)
end

--- Open a new terminal split.
---@param cmd string[]|string
---@param opts table { split_side, split_width_percentage }
function M.open(cmd, opts)
  if is_valid() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  local split_side = opts.split_side or "right"
  local width = math.floor(vim.o.columns * (opts.split_width_percentage or 0.30))

  -- Open a vertical split on the correct side
  if split_side == "left" then
    vim.cmd("topleft " .. width .. "vsplit")
  else
    vim.cmd("botright " .. width .. "vsplit")
  end

  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)

  -- Build the shell command string
  local cmd_str
  if type(cmd) == "table" then
    cmd_str = table.concat(
      vim.tbl_map(function(s)
        -- Simple shell-quote for safety
        return string.format("%q", s)
      end, cmd),
      " "
    )
  else
    cmd_str = cmd
  end

  state.job_id = vim.fn.termopen(cmd_str, {
    on_exit = function(_job, _code, _event)
      vim.schedule(function()
        if state.buf == vim.api.nvim_get_current_buf() then
          -- Buffer is focused; leave it open so user can read output
        end
        state.job_id = nil
      end)
    end,
  })

  vim.bo[state.buf].buflisted = false
  vim.cmd("startinsert")
end

--- Toggle visibility of the terminal.
---@param cmd string[]|string
---@param opts table
function M.toggle(cmd, opts)
  if is_valid() then
    -- Hide by closing the window (buffer stays)
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  else
    -- If buffer exists but no window, re-open in split
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      local split_side = opts.split_side or "right"
      local width = math.floor(vim.o.columns * (opts.split_width_percentage or 0.30))
      if split_side == "left" then
        vim.cmd("topleft " .. width .. "vsplit")
      else
        vim.cmd("botright " .. width .. "vsplit")
      end
      state.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(state.win, state.buf)
    else
      M.open(cmd, opts)
    end
  end
end

--- Focus the terminal window.
function M.focus()
  if is_valid() then
    vim.api.nvim_set_current_win(state.win)
    vim.cmd("startinsert")
  end
end

--- Send text to the terminal job.
---@param text string
function M.send_text(text)
  if state.job_id then
    vim.api.nvim_chan_send(state.job_id, text .. "\n")
  end
end

---@return boolean
function M.is_open()
  return is_valid()
end

--- Reset internal state (e.g. after process exits).
function M.reset()
  state.buf = nil
  state.win = nil
  state.job_id = nil
end

return M
