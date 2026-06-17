--- lua/cursoragent/init.lua
--- Public API for cursoragent.nvim

local M = {}

M.config = require("cursoragent.config")

-- ACP session singleton (used when mode == "acp")
local _acp_client = nil
local _acp_session = nil

--- Get or create the ACP client.
---@return table
local function get_client()
  if not _acp_client then
    _acp_client = require("cursoragent.acp.client").new(M.config.values)
  end
  return _acp_client
end

--- Get or create the ACP session.
---@return table
local function get_session()
  if not _acp_session then
    _acp_session = require("cursoragent.acp.session").new(get_client(), M.config.values)
  end
  return _acp_session
end

--- Ensure ACP client is started and session is initialized.
---@param callback fun(session: table)|nil called when ready
local function ensure_acp_ready(callback)
  local client = get_client()
  local session = get_session()

  local function on_ready()
    if session:is_ready() then
      if callback then
        callback(session)
      end
      return
    end

    session:new_session({
      on_done = function()
        if callback then
          callback(session)
        end
      end,
      on_error = function(err)
        vim.notify("[cursoragent] Session error: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      end,
    })
  end

  if client:is_connected() then
    on_ready()
    return
  end

  client:spawn({
    on_connect = function()
      session:start({
        on_done = on_ready,
        on_error = function(err)
          vim.notify("[cursoragent] Init error: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        end,
      })
    end,
    on_error = function(code)
      vim.notify("[cursoragent] Failed to start agent ACP (exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
    end,
  })
end

--- Setup the plugin with user options.
---@param opts table|nil user config to merge
function M.setup(opts)
  M.config.setup(opts)

  if M.config.values.track_selection then
    require("cursoragent.selection").setup()
  end

  require("cursoragent.commands").setup()

  if M.config.values.auto_start and M.config.values.mode == "acp" then
    vim.defer_fn(function()
      ensure_acp_ready(nil)
    end, 100)
  end
end

--- Called from plugin/cursoragent.lua when user has not called setup().
function M.setup_defaults()
  if not M._setup_called then
    M.setup({})
  end
end

M._setup_called = false

local _original_setup = M.setup
M.setup = function(opts)
  M._setup_called = true
  _original_setup(opts)
end

--- Toggle the agent UI (mode-dependent).
function M.toggle()
  local mode = M.config.values.mode
  if mode == "terminal" then
    require("cursoragent.terminal").toggle()
  elseif mode == "acp" then
    -- For ACP mode, show status if connected, else start
    if _acp_client and _acp_client:is_connected() then
      M.status()
    else
      ensure_acp_ready(function()
        vim.notify("[cursoragent] ACP session ready", vim.log.levels.INFO)
      end)
    end
  elseif mode == "headless" then
    vim.notify("[cursoragent] Headless mode — use :CursorAgentReview or :CursorAgentSend", vim.log.levels.INFO)
  end
end

--- Focus the agent terminal window.
function M.focus()
  local mode = M.config.values.mode
  if mode == "terminal" then
    local terminal = require("cursoragent.terminal")
    if terminal.is_open() then
      terminal.focus()
    else
      terminal.open()
    end
  else
    vim.notify("[cursoragent] focus is only available in terminal mode", vim.log.levels.INFO)
  end
end

--- Send the last visual selection to the agent.
function M.send_selection()
  local sel = require("cursoragent.selection").get_last_selection()
  if not sel or not sel.text or sel.text == "" then
    vim.notify("[cursoragent] No selection to send", vim.log.levels.WARN)
    return
  end

  local context_mod = require("cursoragent.context")
  if sel.filepath and sel.filepath ~= "" then
    context_mod.add_file(sel.filepath, sel.start_line, sel.end_line)
  end

  M.send_text(sel.text)
end

--- Send arbitrary text to the agent.
---@param text string
function M.send_text(text)
  local mode = M.config.values.mode

  if mode == "terminal" then
    require("cursoragent.terminal").send_text(text)
  elseif mode == "acp" then
    ensure_acp_ready(function(session)
      local context_str = require("cursoragent.context").get_context_string()
      session:send_prompt(text, context_str, {
        on_update = function(event)
          -- Display streaming output in a scratch buffer or notify
          local content = event.content or event.text or ""
          if content ~= "" then
            vim.notify("[cursoragent] " .. content:sub(1, 200), vim.log.levels.INFO)
          end

          -- Handle file changes from the session
          if event.type == "file_change" and event.filepath and event.proposed then
            local original = event.original or vim.fn.join(vim.fn.readfile(event.filepath), "\n")
            require("cursoragent.diff").show(original, event.proposed, event.filepath)
          end
        end,
        on_done = function(_result)
          vim.notify("[cursoragent] Done", vim.log.levels.INFO)
        end,
        on_error = function(err)
          vim.notify("[cursoragent] Error: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        end,
      })
    end)
  else
    -- headless: just run and show output
    require("cursoragent.headless").run(text, {
      on_done = function(code, events, _stderr)
        if code == 0 and events then
          require("cursoragent.headless").show_output(events)
        end
      end,
    })
  end
end

--- Add a file to the context.
---@param path string
---@param start_line integer|nil
---@param end_line integer|nil
function M.add_file(path, start_line, end_line)
  local ref = require("cursoragent.context").add_file(path, start_line, end_line)
  vim.notify("[cursoragent] Context: " .. ref, vim.log.levels.INFO)
end

--- Review the current selection or buffer via headless mode.
function M.review()
  local headless = require("cursoragent.headless")
  local sel = require("cursoragent.selection").get_last_selection()

  local text, lang
  if sel and sel.text and sel.text ~= "" then
    text = sel.text
    if sel.filepath and sel.filepath ~= "" then
      lang = vim.filetype.match({ filename = sel.filepath }) or ""
    end
  else
    -- Fall back to current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    text = table.concat(lines, "\n")
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    lang = filepath ~= "" and (vim.filetype.match({ filename = filepath }) or "") or ""
  end

  headless.review(text, {
    language = lang,
    on_done = function(code, events, _stderr)
      if code == 0 and events then
        headless.show_output(events, "Review")
      else
        vim.notify("[cursoragent] Review failed (exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
      end
    end,
  })
  vim.notify("[cursoragent] Running review...", vim.log.levels.INFO)
end

--- Select a model interactively via vim.ui.select.
function M.select_model()
  local models = {
    "Auto",
    "claude-opus-4",
    "claude-sonnet-4-5",
    "gpt-4o",
    "gpt-4o-mini",
    "o3",
    "o4-mini",
    "gemini-2.5-pro",
  }

  vim.ui.select(models, {
    prompt = "Select Cursor Agent model:",
  }, function(choice)
    if not choice then
      return
    end

    M.config.values.model = choice

    local mode = M.config.values.mode
    if mode == "acp" and _acp_session and _acp_session:is_ready() then
      _acp_session:select_model(choice, {
        on_done = function()
          vim.notify("[cursoragent] Model set to: " .. choice, vim.log.levels.INFO)
        end,
      })
    else
      vim.notify("[cursoragent] Model will be used for next session: " .. choice, vim.log.levels.INFO)
    end
  end)
end

--- Set the agent mode (plan, ask, agent).
---@param mode string
function M.set_mode(mode)
  local valid = { plan = true, ask = true, agent = true }
  if not valid[mode] then
    vim.notify("[cursoragent] Invalid mode: " .. tostring(mode) .. ". Use: plan, ask, agent", vim.log.levels.WARN)
    return
  end

  local cfg_mode = M.config.values.mode
  if cfg_mode == "acp" and _acp_session and _acp_session:is_ready() then
    _acp_session:set_mode(mode)
  elseif cfg_mode == "terminal" then
    require("cursoragent.terminal").send_text("/mode " .. mode)
  else
    vim.notify("[cursoragent] Mode switching requires ACP or terminal mode", vim.log.levels.WARN)
  end
end

--- Show current status.
function M.status()
  local lines = {}
  local cfg = M.config.values

  table.insert(lines, "cursoragent.nvim status")
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "mode:       " .. cfg.mode)
  table.insert(lines, "agent_cmd:  " .. M.config.get_agent_cmd())
  table.insert(lines, "model:      " .. (cfg.model or "(auto)"))
  table.insert(lines, "log_level:  " .. cfg.log_level)

  if cfg.mode == "acp" then
    local client_state = _acp_client and _acp_client:get_state() or "not started"
    local session_state = _acp_session and _acp_session:get_state() or "not started"
    table.insert(lines, "")
    table.insert(lines, "ACP client: " .. client_state)
    table.insert(lines, "ACP session:" .. session_state)
  elseif cfg.mode == "terminal" then
    local open = require("cursoragent.terminal").is_open()
    table.insert(lines, "")
    table.insert(lines, "terminal:   " .. (open and "open" or "closed"))
  end

  local ctx = require("cursoragent.context")
  table.insert(lines, "")
  table.insert(lines, "Context files (" .. ctx.count() .. "):")
  table.insert(lines, ctx.format_summary())

  local diff = require("cursoragent.diff")
  if diff.has_pending() then
    local info = diff.get_pending_info()
    table.insert(lines, "")
    table.insert(lines, "Pending diff: " .. (info and info.filepath or "?"))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Check if setup() has been called.
---@return boolean
function M.is_initialized()
  return M._setup_called
end

return M
