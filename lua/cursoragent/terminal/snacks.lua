--- lua/cursoragent/terminal/snacks.lua
--- Terminal provider using Snacks.nvim (folke/snacks.nvim)

local M = {}

--- Check if Snacks.terminal is available.
---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks.terminal ~= nil
end

--- Open or toggle the agent terminal via Snacks.
---@param cmd string[]|string the agent command
---@param opts table { split_side, split_width_percentage }
function M.open(cmd, opts)
  local snacks = require("snacks")
  local position = (opts.split_side == "left") and "left" or "right"
  local width = opts.split_width_percentage or 0.30

  snacks.terminal.toggle(cmd, {
    win = {
      position = position,
      width = width,
    },
  })
end

--- Toggle visibility of the Snacks terminal.
---@param cmd string[]|string
---@param opts table
function M.toggle(cmd, opts)
  M.open(cmd, opts)
end

--- Focus the Snacks terminal window.
function M.focus()
  local snacks = require("snacks")
  -- Snacks.terminal doesn't have a dedicated focus API;
  -- toggle back open if it was open will keep focus
  local ok, buf = pcall(function()
    return snacks.terminal.get()
  end)
  if ok and buf then
    local wins = vim.fn.win_findbuf(buf)
    if wins and wins[1] then
      vim.api.nvim_set_current_win(wins[1])
    end
  end
end

--- Send text to the Snacks terminal.
---@param text string
function M.send_text(text)
  local snacks = require("snacks")
  local ok, buf = pcall(function()
    return snacks.terminal.get()
  end)
  if not ok or not buf then
    return
  end
  local chan = vim.api.nvim_buf_get_var(buf, "terminal_job_id")
  if chan then
    vim.api.nvim_chan_send(chan, text .. "\n")
  end
end

--- Check if terminal is currently open/visible.
---@return boolean
function M.is_open()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    return false
  end
  local get_ok, buf = pcall(function()
    return snacks.terminal.get()
  end)
  if not get_ok or not buf then
    return false
  end
  local wins = vim.fn.win_findbuf(buf)
  return wins ~= nil and #wins > 0
end

return M
