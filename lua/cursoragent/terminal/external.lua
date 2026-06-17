--- lua/cursoragent/terminal/external.lua
--- Opens agent in an external terminal emulator as last resort

local M = {}

--- Detect an available terminal emulator.
---@return string|nil the emulator command
local function detect_emulator()
  local candidates = {
    -- Kitty: supports --hold to keep window open
    { cmd = "kitty", args = "--hold" },
    -- WezTerm
    { cmd = "wezterm", args = "start --" },
    -- Alacritty
    { cmd = "alacritty", args = "-e" },
    -- GNOME Terminal
    { cmd = "gnome-terminal", args = "--" },
    -- xterm
    { cmd = "xterm", args = "-e" },
  }

  for _, cand in ipairs(candidates) do
    if vim.fn.executable(cand.cmd) == 1 then
      return cand.cmd, cand.args
    end
  end
  return nil, nil
end

--- Open the agent command in an external terminal.
---@param cmd string[]|string
---@param _opts table (unused in external mode)
function M.open(cmd, _opts)
  local emulator, emulator_args = detect_emulator()
  if not emulator then
    vim.notify("[cursoragent] No external terminal emulator found. Install kitty, wezterm, alacritty, or xterm.", vim.log.levels.ERROR)
    return
  end

  local agent_cmd
  if type(cmd) == "table" then
    agent_cmd = table.concat(cmd, " ")
  else
    agent_cmd = cmd
  end

  local launch_cmd
  if emulator_args then
    launch_cmd = string.format("%s %s %s", emulator, emulator_args, agent_cmd)
  else
    launch_cmd = string.format("%s %s", emulator, agent_cmd)
  end

  vim.fn.jobstart(launch_cmd, { detach = true })
end

--- External terminal has no toggle concept; always opens a new window.
---@param cmd string[]|string
---@param opts table
function M.toggle(cmd, opts)
  M.open(cmd, opts)
end

--- External terminal cannot be focused from Neovim.
function M.focus()
  vim.notify("[cursoragent] Cannot focus external terminal from Neovim.", vim.log.levels.INFO)
end

--- External terminal cannot receive text from Neovim.
---@param _text string
function M.send_text(_text)
  vim.notify("[cursoragent] Cannot send text to external terminal.", vim.log.levels.WARN)
end

---@return boolean always false for external
function M.is_open()
  return false
end

return M
