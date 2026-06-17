--- lua/cursoragent/commands.lua
--- Defines all user-facing Neovim commands for cursoragent

local M = {}

local function ca()
  return require("cursoragent")
end

--- Setup all CursorAgent* user commands.
function M.setup()
  -- :CursorAgent — toggle (mode-dependent)
  vim.api.nvim_create_user_command("CursorAgent", function()
    ca().toggle()
  end, { desc = "Toggle Cursor Agent" })

  -- :CursorAgentFocus — focus or toggle
  vim.api.nvim_create_user_command("CursorAgentFocus", function()
    ca().focus()
  end, { desc = "Focus Cursor Agent" })

  -- :CursorAgentSend [text] — send visual selection or optional text
  vim.api.nvim_create_user_command("CursorAgentSend", function(args)
    if args.args and args.args ~= "" then
      ca().send_text(args.args)
    else
      ca().send_selection()
    end
  end, {
    desc = "Send visual selection or text to Cursor Agent",
    range = true,
    nargs = "?",
  })

  -- :CursorAgentAdd <path> [start] [end]
  vim.api.nvim_create_user_command("CursorAgentAdd", function(args)
    local parts = vim.split(vim.trim(args.args), "%s+")
    local path = parts[1] or "%"
    if path == "%" then
      path = vim.api.nvim_buf_get_name(0)
    end
    local start_line = tonumber(parts[2])
    local end_line = tonumber(parts[3])
    ca().add_file(path, start_line, end_line)
  end, {
    desc = "Add file/range to Cursor Agent context",
    nargs = "+",
    complete = "file",
  })

  -- :CursorAgentTreeAdd — add file from active file tree
  vim.api.nvim_create_user_command("CursorAgentTreeAdd", function()
    require("cursoragent.integrations").add_current_to_context()
  end, { desc = "Add file under cursor in file tree to context" })

  -- :CursorAgentSelectModel — select model interactively
  vim.api.nvim_create_user_command("CursorAgentSelectModel", function()
    ca().select_model()
  end, { desc = "Select Cursor Agent model" })

  -- :CursorAgentMode {plan|ask|agent}
  vim.api.nvim_create_user_command("CursorAgentMode", function(args)
    local mode = vim.trim(args.args)
    if mode == "" then
      vim.notify("[cursoragent] Usage: CursorAgentMode {plan|ask|agent}", vim.log.levels.WARN)
      return
    end
    ca().set_mode(mode)
  end, {
    desc = "Set Cursor Agent mode (plan|ask|agent)",
    nargs = 1,
    complete = function()
      return { "plan", "ask", "agent" }
    end,
  })

  -- :CursorAgentReview — review visual selection or current buffer via headless
  vim.api.nvim_create_user_command("CursorAgentReview", function()
    ca().review()
  end, {
    desc = "Review selection or buffer with Cursor Agent (headless)",
    range = true,
  })

  -- :CursorAgentDiffAccept
  vim.api.nvim_create_user_command("CursorAgentDiffAccept", function()
    require("cursoragent.diff").accept()
  end, { desc = "Accept pending Cursor Agent diff" })

  -- :CursorAgentDiffDeny
  vim.api.nvim_create_user_command("CursorAgentDiffDeny", function()
    require("cursoragent.diff").deny()
  end, { desc = "Deny pending Cursor Agent diff" })

  -- :CursorAgentStatus
  vim.api.nvim_create_user_command("CursorAgentStatus", function()
    ca().status()
  end, { desc = "Show Cursor Agent status" })
end

return M
