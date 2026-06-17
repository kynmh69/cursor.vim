--- lua/cursoragent/acp/client.lua
--- Manages the "agent acp" subprocess via vim.system() (Neovim 0.10+)

local M = {}

local jsonrpc = require("cursoragent.acp.jsonrpc")
local logger = require("cursoragent.logger")

--- Client state machine values
M.STATE = {
  IDLE = "idle",
  CONNECTING = "connecting",
  CONNECTED = "connected",
  ERROR = "error",
  STOPPED = "stopped",
}

--- Creates a new ACP client instance.
---@param config table the cursoragent config
---@return table client instance
function M.new(config)
  local self = {
    config = config,
    state = M.STATE.IDLE,
    --- vim.system() process object
    _process = nil,
    --- Pending request callbacks: id → { resolve, reject, timer }
    _pending = {},
    --- Registered message handlers (for notifications/updates)
    _handlers = {},
    --- Stdout accumulation buffer
    _stdout_buf = "",
    --- Stderr accumulation buffer
    _stderr_buf = "",
    --- Input pipe for writing to the process
    _stdin = nil,
  }

  setmetatable(self, { __index = M })
  return self
end

--- Register a handler for incoming messages (notifications and responses).
--- The callback receives the parsed JSON-RPC message table.
---@param callback fun(msg: table)
function M:on_message(callback)
  table.insert(self._handlers, callback)
end

--- Remove all message handlers.
function M:clear_handlers()
  self._handlers = {}
end

--- Dispatch a parsed message to all registered handlers.
---@param msg table parsed JSON-RPC message
function M:_dispatch(msg)
  for _, handler in ipairs(self._handlers) do
    local ok, err = pcall(handler, msg)
    if not ok then
      logger.error("Message handler error: %s", tostring(err))
    end
  end
end

--- Handle incoming stdout data.
---@param data string new data chunk
function M:_on_stdout(data)
  if not data or data == "" then
    return
  end

  local messages = jsonrpc.parse_message(data)
  for _, msg in ipairs(messages) do
    vim.schedule(function()
      -- Check if this is a response to a pending request
      if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
        local pending = self._pending[msg.id]
        if pending then
          self._pending[msg.id] = nil
          -- Cancel timeout timer if set
          if pending.timer then
            pending.timer:stop()
            pending.timer:close()
          end

          if msg.error then
            if pending.reject then
              pending.reject(msg.error)
            end
          else
            if pending.resolve then
              pending.resolve(msg.result)
            end
          end
          return
        end
      end

      -- Otherwise dispatch to general handlers (notifications, etc.)
      self:_dispatch(msg)
    end)
  end
end

--- Handle incoming stderr data.
---@param data string new data chunk
function M:_on_stderr(data)
  if not data or data == "" then
    return
  end

  self._stderr_buf = self._stderr_buf .. data
  -- Log stderr lines as debug output
  local lines = vim.split(self._stderr_buf, "\n")
  -- Keep the last potentially incomplete line in the buffer
  self._stderr_buf = lines[#lines]
  for i = 1, #lines - 1 do
    if lines[i] ~= "" then
      logger.debug("agent stderr: %s", lines[i])
    end
  end
end

--- Start the agent ACP subprocess.
---@param opts table|nil optional overrides: { on_connect, on_error }
---@return boolean true if started successfully
function M:spawn(opts)
  opts = opts or {}

  if self.state ~= M.STATE.IDLE and self.state ~= M.STATE.ERROR and self.state ~= M.STATE.STOPPED then
    logger.warn("Client already in state: %s", self.state)
    return false
  end

  local ok_cfg, config_mod = pcall(require, "cursoragent.config")
  local agent_cmd = (ok_cfg and config_mod.get_agent_cmd()) or "agent"

  local cmd = { agent_cmd, "acp" }

  -- Add model if configured
  local model = self.config and self.config.model
  if model then
    table.insert(cmd, "--model")
    table.insert(cmd, model)
  end

  self.state = M.STATE.CONNECTING
  jsonrpc.reset_buffer()

  logger.debug("Spawning agent ACP: %s", table.concat(cmd, " "))

  -- We use vim.system with stdin pipe for writing
  -- stdout and stderr handlers for reading
  local stdout_chunks = {}
  local self_ref = self

  local process_opts = {
    stdin = true, -- request a pipe for stdin
    stdout = function(err, data)
      if err then
        logger.error("stdout error: %s", tostring(err))
        return
      end
      if data then
        self_ref:_on_stdout(data)
      end
    end,
    stderr = function(err, data)
      if err then
        return
      end
      if data then
        self_ref:_on_stderr(data)
      end
    end,
  }

  local ok, result = pcall(vim.system, cmd, process_opts, function(completed)
    vim.schedule(function()
      local exit_code = completed.code
      logger.debug("agent ACP process exited with code %d", exit_code)
      self_ref.state = M.STATE.STOPPED
      self_ref._process = nil
      self_ref._stdin = nil

      -- Reject all pending requests
      for id, pending in pairs(self_ref._pending) do
        if pending.timer then
          pending.timer:stop()
          pending.timer:close()
        end
        if pending.reject then
          pending.reject({ code = -1, message = "Process exited with code " .. exit_code })
        end
      end
      self_ref._pending = {}

      if opts.on_error then
        opts.on_error(exit_code)
      end
    end)
  end)

  if not ok then
    self.state = M.STATE.ERROR
    logger.error("Failed to spawn agent ACP: %s", tostring(result))
    if opts.on_error then
      opts.on_error(-1)
    end
    return false
  end

  self._process = result
  -- Store stdin write handle
  self._stdin = result

  self.state = M.STATE.CONNECTED
  logger.info("agent ACP process started")

  if opts.on_connect then
    vim.schedule(opts.on_connect)
  end

  return true
end

--- Send raw data to the process stdin.
---@param data string data to write
---@return boolean success
function M:send(data)
  if not self._process or self.state ~= M.STATE.CONNECTED then
    logger.warn("Cannot send: client not connected (state: %s)", self.state)
    return false
  end

  local ok, err = pcall(function()
    self._process:write(data)
  end)

  if not ok then
    logger.error("Failed to write to stdin: %s", tostring(err))
    self.state = M.STATE.ERROR
    return false
  end

  return true
end

--- Send a JSON-RPC request and register callbacks for the response.
---@param method string RPC method
---@param params table|nil method params
---@param opts table|nil { resolve, reject, timeout_ms }
---@return number|nil the request ID, or nil on failure
function M:request(method, params, opts)
  opts = opts or {}

  local framed, req_id = jsonrpc.encode_request(method, params)

  local pending_entry = {
    resolve = opts.resolve,
    reject = opts.reject,
    timer = nil,
  }

  -- Set up optional timeout
  local timeout_ms = opts.timeout_ms
  if timeout_ms and timeout_ms > 0 then
    local timer = vim.loop.new_timer()
    pending_entry.timer = timer
    timer:start(
      timeout_ms,
      0,
      vim.schedule_wrap(function()
        timer:close()
        if self._pending[req_id] then
          self._pending[req_id] = nil
          if opts.reject then
            opts.reject({ code = -32000, message = "Request timed out" })
          end
        end
      end)
    )
  end

  self._pending[req_id] = pending_entry

  if not self:send(framed) then
    self._pending[req_id] = nil
    if pending_entry.timer then
      pending_entry.timer:stop()
      pending_entry.timer:close()
    end
    return nil
  end

  logger.debug("Sent request id=%d method=%s", req_id, method)
  return req_id
end

--- Send a JSON-RPC notification (no response expected).
---@param method string RPC method
---@param params table|nil method params
---@return boolean success
function M:notify(method, params)
  local framed = jsonrpc.encode_notification(method, params)
  logger.debug("Sent notification method=%s", method)
  return self:send(framed)
end

--- Stop the agent ACP process gracefully.
function M:stop()
  if not self._process then
    self.state = M.STATE.STOPPED
    return
  end

  -- Close stdin to signal EOF to the process
  local ok = pcall(function()
    self._process:write(nil) -- signal EOF / close stdin
  end)

  -- Give it a moment then kill if needed
  local timer = vim.loop.new_timer()
  local self_ref = self
  timer:start(2000, 0, function()
    timer:close()
    if self_ref._process then
      pcall(function()
        self_ref._process:kill(9)
      end)
    end
  end)

  self.state = M.STATE.STOPPED
  logger.debug("Stopped agent ACP client")
end

--- Check if the client is currently connected and ready.
---@return boolean
function M:is_connected()
  return self.state == M.STATE.CONNECTED
end

--- Get the current state.
---@return string
function M:get_state()
  return self.state
end

return M
