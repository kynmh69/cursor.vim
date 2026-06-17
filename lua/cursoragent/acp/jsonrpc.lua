--- lua/cursoragent/acp/jsonrpc.lua
--- JSON-RPC 2.0 implementation with LSP-style Content-Length framing
--- and newline-delimited JSON fallback

local M = {}

--- Auto-incrementing request ID counter
local id_counter = 0

--- Internal buffer for accumulating partial data
local parse_buffer = ""

--- Encode a JSON-RPC 2.0 request with Content-Length framing.
---@param method string the RPC method name
---@param params table|nil method parameters
---@return string the framed message ready to send
---@return number the request ID
function M.encode_request(method, params)
  id_counter = id_counter + 1
  local current_id = id_counter

  local msg = {
    jsonrpc = "2.0",
    id = current_id,
    method = method,
    params = params or vim.empty_dict(),
  }

  local body = vim.json.encode(msg)
  local framed = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
  return framed, current_id
end

--- Encode a JSON-RPC 2.0 notification (no id, no response expected).
---@param method string the RPC method name
---@param params table|nil method parameters
---@return string the framed message ready to send
function M.encode_notification(method, params)
  local msg = {
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }

  local body = vim.json.encode(msg)
  return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

--- Encode a JSON-RPC 2.0 response (for server → client responses if needed).
---@param id number|string request ID being responded to
---@param result any the result value
---@return string the framed message
function M.encode_response(id, result)
  local msg = {
    jsonrpc = "2.0",
    id = id,
    result = result,
  }
  local body = vim.json.encode(msg)
  return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

--- Encode a JSON-RPC 2.0 error response.
---@param id number|string request ID
---@param code number error code
---@param message string error message
---@param data any|nil optional error data
---@return string the framed message
function M.encode_error(id, code, message, data)
  local err = { code = code, message = message }
  if data ~= nil then
    err.data = data
  end
  local msg = {
    jsonrpc = "2.0",
    id = id,
    error = err,
  }
  local body = vim.json.encode(msg)
  return string.format("Content-Length: %d\r\n\r\n%s", #body, body)
end

--- Reset the internal parse buffer.
function M.reset_buffer()
  parse_buffer = ""
end

--- Try to parse Content-Length framed messages from accumulated data.
--- Returns a list of parsed JSON objects extracted from the buffer.
--- Any remaining incomplete data is kept in the buffer for the next call.
---@param data string new data chunk received
---@return table[] list of parsed JSON objects (may be empty)
function M.parse_message(data)
  parse_buffer = parse_buffer .. (data or "")
  local results = {}

  while true do
    -- Try Content-Length framing first (LSP style)
    local header_end = parse_buffer:find("\r\n\r\n", 1, true)
    if header_end then
      local header_section = parse_buffer:sub(1, header_end - 1)
      local content_length = header_section:match("Content%-Length:%s*(%d+)")

      if content_length then
        content_length = tonumber(content_length)
        local body_start = header_end + 4 -- skip \r\n\r\n
        local body_end = body_start + content_length - 1

        if #parse_buffer >= body_end then
          local body = parse_buffer:sub(body_start, body_end)
          parse_buffer = parse_buffer:sub(body_end + 1)

          local ok, parsed = pcall(vim.json.decode, body)
          if ok and type(parsed) == "table" then
            table.insert(results, parsed)
          end
          -- Continue loop to check for more messages
        else
          -- Not enough data yet, wait for more
          break
        end
      else
        -- Header section without Content-Length, skip this potential false positive
        -- Try newline-delimited fallback below
        break
      end
    else
      -- No Content-Length framing found; try newline-delimited JSON
      -- Look for complete JSON lines
      local found_any = false
      while true do
        local newline_pos = parse_buffer:find("\n", 1, true)
        if not newline_pos then
          break
        end

        local line = parse_buffer:sub(1, newline_pos - 1)
        -- Remove trailing \r if present (handle \r\n)
        line = line:gsub("\r$", "")
        parse_buffer = parse_buffer:sub(newline_pos + 1)

        -- Skip empty lines
        if line ~= "" then
          local ok, parsed = pcall(vim.json.decode, line)
          if ok and type(parsed) == "table" then
            table.insert(results, parsed)
            found_any = true
          end
          -- If parse fails, it might be partial JSON; but since we split on newline,
          -- we assume each line is a complete JSON object
        end
      end

      if not found_any then
        break
      end
      break
    end
  end

  return results
end

--- Get the current value of the ID counter (useful for testing).
---@return number
function M.get_id_counter()
  return id_counter
end

--- Reset the ID counter (useful for testing).
function M.reset_id_counter()
  id_counter = 0
end

--- Standard JSON-RPC error codes
M.ERROR_CODES = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
}

return M
