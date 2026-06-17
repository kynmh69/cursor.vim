--- lua/cursoragent/acp/session.lua
--- ACP session lifecycle state machine

local M = {}

local logger = require("cursoragent.logger")
local permission = require("cursoragent.acp.permission")

--- Session states
M.STATE = {
  IDLE = "idle",
  INITIALIZING = "initializing",
  AUTHENTICATING = "authenticating",
  READY = "ready",
  PROMPTING = "prompting",
  WAITING_PERMISSION = "waiting_permission",
  ERROR = "error",
}

--- Create a new session instance.
---@param client table ACP client instance
---@param config table cursoragent config values
---@return table session
function M.new(client, config)
  local self = {
    client = client,
    config = config,
    state = M.STATE.IDLE,
    session_id = nil,
    _on_update = nil,
    _on_done = nil,
    _on_error = nil,
    _pending_permissions = {},
    _handler_registered = false,
  }
  setmetatable(self, { __index = M })
  return self
end

function M:on_update(fn)
  self._on_update = fn
end

function M:on_done(fn)
  self._on_done = fn
end

function M:on_error(fn)
  self._on_error = fn
end

function M:_emit_update(event)
  if self._on_update then
    pcall(self._on_update, event)
  end
end

function M:_emit_done(result)
  if self._on_done then
    pcall(self._on_done, result)
  end
end

function M:_emit_error(err)
  self.state = M.STATE.ERROR
  if self._on_error then
    pcall(self._on_error, err)
  else
    logger.error("ACP session error: %s", vim.inspect(err))
  end
end

function M:_ensure_handler()
  if self._handler_registered then
    return
  end
  self._handler_registered = true
  local self_ref = self
  self.client:on_message(function(msg)
    self_ref:_handle_message(msg)
  end)
end

function M:_handle_message(msg)
  local method = msg.method
  if method == "session/update" then
    self:_handle_session_update(msg.params or msg)
  elseif method == "session/done" then
    self:_handle_session_done(msg.params or msg)
  elseif method == "session/request_permission" then
    self:_handle_permission_request(msg.params or msg)
  elseif method == "session/error" then
    self:_emit_error(msg.params or { message = "Unknown session error" })
  else
    logger.debug("Unhandled ACP message method: %s", tostring(method))
  end
end

function M:_handle_session_update(params)
  if self.state == M.STATE.PROMPTING then
    self:_emit_update(params)
  end
end

function M:_handle_session_done(params)
  if self.state == M.STATE.PROMPTING or self.state == M.STATE.WAITING_PERMISSION then
    self.state = M.STATE.READY
    self:_emit_done(params)
  end
end

function M:_handle_permission_request(params)
  self.state = M.STATE.WAITING_PERMISSION
  self._pending_permissions[params.id or params.request_id] = params

  local perm_mode = (self.config.acp and self.config.acp.permission and self.config.acp.permission.mode) or "ask"

  local self_ref = self
  permission.handle(
    params,
    function(req_id, always)
      self_ref:approve_permission(req_id, always)
    end,
    function(req_id)
      self_ref:deny_permission(req_id)
    end,
    perm_mode
  )
end

--- Send initialize request to start the ACP handshake.
---@param opts table|nil { on_done, on_error }
function M:start(opts)
  opts = opts or {}
  self:_ensure_handler()
  self.state = M.STATE.INITIALIZING

  local self_ref = self
  self.client:request("initialize", { version = "1.0" }, {
    resolve = function(result)
      logger.debug("ACP initialized: %s", vim.inspect(result))
      self_ref.state = M.STATE.AUTHENTICATING
      if self_ref.config.acp and self_ref.config.acp.auto_authenticate then
        self_ref:authenticate({ on_done = opts.on_done, on_error = opts.on_error })
      else
        self_ref.state = M.STATE.READY
        if opts.on_done then
          opts.on_done(result)
        end
      end
    end,
    reject = function(err)
      logger.error("ACP initialize failed: %s", vim.inspect(err))
      self_ref:_emit_error(err)
      if opts.on_error then
        opts.on_error(err)
      end
    end,
    timeout_ms = 10000,
  })
end

--- Send authenticate request with API key.
---@param opts table|nil { on_done, on_error }
function M:authenticate(opts)
  opts = opts or {}
  local api_key_env = self.config.api_key_env or "CURSOR_API_KEY"
  local api_key = vim.env[api_key_env]

  if not api_key or api_key == "" then
    local err = { message = string.format("Environment variable %s not set", api_key_env) }
    logger.error(err.message)
    self:_emit_error(err)
    if opts.on_error then
      opts.on_error(err)
    end
    return
  end

  local self_ref = self
  self.client:request("authenticate", { api_key = api_key }, {
    resolve = function(result)
      logger.debug("ACP authenticated")
      self_ref.state = M.STATE.READY
      if opts.on_done then
        opts.on_done(result)
      end
    end,
    reject = function(err)
      logger.error("ACP authenticate failed: %s", vim.inspect(err))
      self_ref:_emit_error(err)
      if opts.on_error then
        opts.on_error(err)
      end
    end,
    timeout_ms = 10000,
  })
end

--- Create a new agent session.
---@param opts table|nil { model, mode, on_done, on_error }
function M:new_session(opts)
  opts = opts or {}
  if self.state ~= M.STATE.READY then
    local err = { message = string.format("Cannot create session in state: %s", self.state) }
    if opts.on_error then
      opts.on_error(err)
    end
    return
  end

  local params = {}
  local model = opts.model or (self.config and self.config.model)
  if model then
    params.model = model
  end
  if opts.mode then
    params.mode = opts.mode
  end

  local self_ref = self
  self.client:request("session/new", params, {
    resolve = function(result)
      self_ref.session_id = result and result.session_id
      logger.debug("ACP session created: %s", tostring(self_ref.session_id))
      if opts.on_done then
        opts.on_done(result)
      end
    end,
    reject = function(err)
      logger.error("ACP session/new failed: %s", vim.inspect(err))
      self_ref:_emit_error(err)
      if opts.on_error then
        opts.on_error(err)
      end
    end,
    timeout_ms = 10000,
  })
end

--- Send a prompt to the current session.
---@param text string the prompt text
---@param context string|nil additional context (@file references etc.)
---@param opts table|nil { on_update, on_done, on_error }
function M:send_prompt(text, context, opts)
  opts = opts or {}
  if self.state ~= M.STATE.READY then
    local err = { message = string.format("Cannot send prompt in state: %s", self.state) }
    if opts.on_error then
      opts.on_error(err)
    end
    return
  end

  if opts.on_update then
    self._on_update = opts.on_update
  end
  if opts.on_done then
    self._on_done = opts.on_done
  end
  if opts.on_error then
    self._on_error = opts.on_error
  end

  self.state = M.STATE.PROMPTING

  local params = { text = text, session_id = self.session_id }
  if context and context ~= "" then
    params.context = context
  end

  local self_ref = self
  self.client:request("session/prompt", params, {
    resolve = function(_result)
      logger.debug("session/prompt acknowledged")
    end,
    reject = function(err)
      self_ref.state = M.STATE.READY
      logger.error("session/prompt failed: %s", vim.inspect(err))
      self_ref:_emit_error(err)
    end,
    timeout_ms = 5000,
  })
end

--- Approve a pending permission request.
---@param req_id any
---@param always boolean
function M:approve_permission(req_id, always)
  self._pending_permissions[req_id] = nil
  self.client:notify("session/approve_permission", { request_id = req_id, always = always or false })
  if self.state == M.STATE.WAITING_PERMISSION then
    self.state = M.STATE.PROMPTING
  end
  logger.debug("Approved permission request id=%s always=%s", tostring(req_id), tostring(always))
end

--- Deny a pending permission request.
---@param req_id any
function M:deny_permission(req_id)
  self._pending_permissions[req_id] = nil
  self.client:notify("session/deny_permission", { request_id = req_id })
  if self.state == M.STATE.WAITING_PERMISSION then
    self.state = M.STATE.READY
  end
  logger.debug("Denied permission request id=%s", tostring(req_id))
end

--- Select a model for the session.
---@param model string
---@param opts table|nil { on_done, on_error }
function M:select_model(model, opts)
  opts = opts or {}
  self.client:request("session/set_model", { model = model }, {
    resolve = function(result)
      logger.info("Model set to: %s", model)
      if opts.on_done then
        opts.on_done(result)
      end
    end,
    reject = function(err)
      logger.error("Failed to set model: %s", vim.inspect(err))
      if opts.on_error then
        opts.on_error(err)
      end
    end,
    timeout_ms = 5000,
  })
end

--- Switch agent mode.
---@param mode string "plan"|"ask"|"agent"
---@param opts table|nil { on_done, on_error }
function M:set_mode(mode, opts)
  opts = opts or {}
  self.client:request("session/set_mode", { mode = mode }, {
    resolve = function(result)
      logger.info("Mode set to: %s", mode)
      if opts.on_done then
        opts.on_done(result)
      end
    end,
    reject = function(err)
      logger.error("Failed to set mode: %s", vim.inspect(err))
      if opts.on_error then
        opts.on_error(err)
      end
    end,
    timeout_ms = 5000,
  })
end

---@return string
function M:get_state()
  return self.state
end

---@return boolean
function M:is_ready()
  return self.state == M.STATE.READY
end

return M
