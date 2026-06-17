--- tests/cursoragent/jsonrpc_spec.lua
--- Tests for lua/cursoragent/acp/jsonrpc.lua

local jsonrpc = require("cursoragent.acp.jsonrpc")

describe("cursoragent.acp.jsonrpc", function()
  before_each(function()
    -- Reset ID counter and parse buffer before each test
    jsonrpc.reset_id_counter()
    jsonrpc.reset_buffer()
  end)

  describe("encode_request()", function()
    it("produces a valid JSON-RPC 2.0 request", function()
      local framed, id = jsonrpc.encode_request("initialize", { version = "1.0" })

      assert.equals(1, id)
      assert.is_string(framed)

      -- Should have Content-Length header
      local header, body = framed:match("^(Content%-Length: %d+)\r\n\r\n(.+)$")
      assert.is_string(header)
      assert.is_string(body)

      -- Body should be valid JSON
      local ok, decoded = pcall(vim.json.decode, body)
      assert.is_true(ok)
      assert.equals("2.0", decoded.jsonrpc)
      assert.equals(1, decoded.id)
      assert.equals("initialize", decoded.method)
      assert.is_table(decoded.params)
      assert.equals("1.0", decoded.params.version)
    end)

    it("auto-increments the ID", function()
      local _, id1 = jsonrpc.encode_request("method1", {})
      local _, id2 = jsonrpc.encode_request("method2", {})
      local _, id3 = jsonrpc.encode_request("method3", {})

      assert.equals(1, id1)
      assert.equals(2, id2)
      assert.equals(3, id3)
    end)

    it("handles nil params gracefully", function()
      local framed, id = jsonrpc.encode_request("ping", nil)
      assert.is_string(framed)
      assert.is_number(id)

      local _header, body = framed:match("^Content%-Length: %d+\r\n\r\n(.+)$")
      local ok, decoded = pcall(vim.json.decode, body)
      assert.is_true(ok)
      assert.equals("ping", decoded.method)
    end)

    it("Content-Length matches body byte length", function()
      local framed, _id = jsonrpc.encode_request("test", { key = "value" })
      local length_str, body = framed:match("^Content%-Length: (%d+)\r\n\r\n(.+)$")
      assert.is_string(length_str)
      assert.is_string(body)
      assert.equals(tonumber(length_str), #body)
    end)

    it("resets ID counter correctly", function()
      jsonrpc.encode_request("a", {})
      jsonrpc.encode_request("b", {})
      assert.equals(2, jsonrpc.get_id_counter())

      jsonrpc.reset_id_counter()
      assert.equals(0, jsonrpc.get_id_counter())

      local _, id = jsonrpc.encode_request("c", {})
      assert.equals(1, id)
    end)
  end)

  describe("encode_notification()", function()
    it("produces a valid JSON-RPC 2.0 notification (no id)", function()
      local framed = jsonrpc.encode_notification("session/update", { text = "hello" })
      assert.is_string(framed)

      local _header, body = framed:match("^Content%-Length: %d+\r\n\r\n(.+)$")
      local ok, decoded = pcall(vim.json.decode, body)
      assert.is_true(ok)

      assert.equals("2.0", decoded.jsonrpc)
      assert.equals("session/update", decoded.method)
      assert.is_nil(decoded.id)
      assert.is_table(decoded.params)
      assert.equals("hello", decoded.params.text)
    end)

    it("does not increment the ID counter", function()
      local counter_before = jsonrpc.get_id_counter()
      jsonrpc.encode_notification("test", {})
      assert.equals(counter_before, jsonrpc.get_id_counter())
    end)

    it("Content-Length matches body byte length", function()
      local framed = jsonrpc.encode_notification("notify", { x = 42 })
      local length_str, body = framed:match("^Content%-Length: (%d+)\r\n\r\n(.+)$")
      assert.equals(tonumber(length_str), #body)
    end)
  end)

  describe("parse_message() with Content-Length framing", function()
    it("parses a single Content-Length framed message", function()
      local msg = { jsonrpc = "2.0", id = 1, result = { ok = true } }
      local body = vim.json.encode(msg)
      local framed = string.format("Content-Length: %d\r\n\r\n%s", #body, body)

      local results = jsonrpc.parse_message(framed)
      assert.equals(1, #results)
      assert.equals("2.0", results[1].jsonrpc)
      assert.equals(1, results[1].id)
      assert.is_true(results[1].result.ok)
    end)

    it("parses multiple Content-Length framed messages in one chunk", function()
      local msg1 = { jsonrpc = "2.0", id = 1, result = "first" }
      local msg2 = { jsonrpc = "2.0", id = 2, result = "second" }
      local body1 = vim.json.encode(msg1)
      local body2 = vim.json.encode(msg2)
      local framed = string.format("Content-Length: %d\r\n\r\n%sContent-Length: %d\r\n\r\n%s",
        #body1, body1, #body2, body2)

      local results = jsonrpc.parse_message(framed)
      assert.equals(2, #results)
      assert.equals("first", results[1].result)
      assert.equals("second", results[2].result)
    end)

    it("handles partial data (buffers incomplete messages)", function()
      local msg = { jsonrpc = "2.0", id = 1, result = "done" }
      local body = vim.json.encode(msg)
      local full = string.format("Content-Length: %d\r\n\r\n%s", #body, body)

      -- Send only half
      local half = full:sub(1, math.floor(#full / 2))
      local results1 = jsonrpc.parse_message(half)
      assert.equals(0, #results1)

      -- Send the rest
      local rest = full:sub(math.floor(#full / 2) + 1)
      local results2 = jsonrpc.parse_message(rest)
      assert.equals(1, #results2)
      assert.equals("done", results2[1].result)
    end)

    it("handles message followed by partial next message", function()
      local msg1 = { jsonrpc = "2.0", id = 1, result = "a" }
      local msg2 = { jsonrpc = "2.0", id = 2, result = "b" }
      local body1 = vim.json.encode(msg1)
      local body2 = vim.json.encode(msg2)

      local framed1 = string.format("Content-Length: %d\r\n\r\n%s", #body1, body1)
      local framed2_start = string.format("Content-Length: %d\r\n\r\n%s", #body2, body2:sub(1, 5))
      local framed2_end = body2:sub(6)

      -- First chunk: complete msg1 + partial msg2 header+body
      local results1 = jsonrpc.parse_message(framed1 .. framed2_start)
      assert.equals(1, #results1)
      assert.equals("a", results1[1].result)

      -- Second chunk: rest of msg2 body
      local results2 = jsonrpc.parse_message(framed2_end)
      assert.equals(1, #results2)
      assert.equals("b", results2[1].result)
    end)
  end)

  describe("parse_message() with newline-delimited JSON", function()
    it("parses newline-delimited JSON messages", function()
      jsonrpc.reset_buffer()
      local msg1 = vim.json.encode({ jsonrpc = "2.0", method = "update", params = { n = 1 } })
      local msg2 = vim.json.encode({ jsonrpc = "2.0", method = "update", params = { n = 2 } })
      local data = msg1 .. "\n" .. msg2 .. "\n"

      local results = jsonrpc.parse_message(data)
      assert.equals(2, #results)
      assert.equals(1, results[1].params.n)
      assert.equals(2, results[2].params.n)
    end)

    it("handles CRLF line endings in newline-delimited mode", function()
      jsonrpc.reset_buffer()
      local msg = vim.json.encode({ jsonrpc = "2.0", method = "ping", params = {} })
      local data = msg .. "\r\n"

      local results = jsonrpc.parse_message(data)
      assert.equals(1, #results)
      assert.equals("ping", results[1].method)
    end)

    it("ignores empty lines in newline-delimited mode", function()
      jsonrpc.reset_buffer()
      local msg = vim.json.encode({ jsonrpc = "2.0", method = "hi", params = {} })
      local data = "\n\n" .. msg .. "\n\n"

      local results = jsonrpc.parse_message(data)
      assert.equals(1, #results)
    end)
  end)

  describe("encode_response()", function()
    it("produces a valid JSON-RPC 2.0 response", function()
      local framed = jsonrpc.encode_response(42, { status = "ok" })
      local _header, body = framed:match("^Content%-Length: %d+\r\n\r\n(.+)$")
      local ok, decoded = pcall(vim.json.decode, body)
      assert.is_true(ok)
      assert.equals("2.0", decoded.jsonrpc)
      assert.equals(42, decoded.id)
      assert.is_table(decoded.result)
      assert.equals("ok", decoded.result.status)
    end)
  end)

  describe("encode_error()", function()
    it("produces a valid JSON-RPC 2.0 error response", function()
      local framed = jsonrpc.encode_error(5, -32601, "Method not found")
      local _header, body = framed:match("^Content%-Length: %d+\r\n\r\n(.+)$")
      local ok, decoded = pcall(vim.json.decode, body)
      assert.is_true(ok)
      assert.equals("2.0", decoded.jsonrpc)
      assert.equals(5, decoded.id)
      assert.is_table(decoded.error)
      assert.equals(-32601, decoded.error.code)
      assert.equals("Method not found", decoded.error.message)
    end)
  end)

  describe("ERROR_CODES", function()
    it("defines standard JSON-RPC error codes", function()
      assert.equals(-32700, jsonrpc.ERROR_CODES.PARSE_ERROR)
      assert.equals(-32600, jsonrpc.ERROR_CODES.INVALID_REQUEST)
      assert.equals(-32601, jsonrpc.ERROR_CODES.METHOD_NOT_FOUND)
      assert.equals(-32602, jsonrpc.ERROR_CODES.INVALID_PARAMS)
      assert.equals(-32603, jsonrpc.ERROR_CODES.INTERNAL_ERROR)
    end)
  end)

  describe("reset_buffer()", function()
    it("clears the internal parse buffer", function()
      -- Feed partial data
      local msg = { jsonrpc = "2.0", id = 1, result = "x" }
      local body = vim.json.encode(msg)
      local partial = string.format("Content-Length: %d\r\n\r\n%s", #body, body:sub(1, 3))
      jsonrpc.parse_message(partial)

      -- Reset and feed full message
      jsonrpc.reset_buffer()
      local full = string.format("Content-Length: %d\r\n\r\n%s", #body, body)
      local results = jsonrpc.parse_message(full)
      assert.equals(1, #results)
    end)
  end)
end)
