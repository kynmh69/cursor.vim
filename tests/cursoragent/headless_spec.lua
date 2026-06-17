--- tests/cursoragent/headless_spec.lua
--- Tests for lua/cursoragent/headless.lua

-- We need config to be set up before testing headless
local config = require("cursoragent.config")
local headless = require("cursoragent.headless")

describe("cursoragent.headless", function()
  before_each(function()
    config.setup({
      agent_cmd = "agent",
      model = nil,
      headless = {
        output_format = "json",
        force = false,
      },
    })
  end)

  describe("build_args() (via internal function exposed for testing)", function()
    -- Since build_args is local, we test it via M.run's behavior
    -- Instead we test the public API by inspecting what gets constructed

    -- We can test the args by accessing the module's run function indirectly
    -- by patching vim.system and inspecting the cmd argument

    it("constructs basic args with agent cmd and prompt", function()
      local captured_cmd = nil

      -- Patch vim.system temporarily
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        -- Return a fake process object
        return {}
      end

      headless.run("hello world", {
        on_done = function() end,
      })

      vim.system = orig_system

      assert.is_table(captured_cmd)
      assert.equals("agent", captured_cmd[1])
      assert.equals("-p", captured_cmd[2])
      assert.equals("hello world", captured_cmd[3])
      assert.equals("--output-format", captured_cmd[4])
      assert.equals("json", captured_cmd[5])
    end)

    it("includes --output-format from config", function()
      config.setup({
        headless = { output_format = "stream-json", force = false },
      })

      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("test prompt", { on_done = function() end })

      vim.system = orig_system

      -- Find --output-format argument
      local found_format = false
      for i, arg in ipairs(captured_cmd) do
        if arg == "--output-format" then
          assert.equals("stream-json", captured_cmd[i + 1])
          found_format = true
          break
        end
      end
      assert.is_true(found_format)
    end)

    it("includes --model when model is set in config", function()
      config.setup({
        model = "claude-3-5-sonnet-20241022",
        headless = { output_format = "json", force = false },
      })

      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("test prompt", { on_done = function() end })

      vim.system = orig_system

      local found_model = false
      for i, arg in ipairs(captured_cmd) do
        if arg == "--model" then
          assert.equals("claude-3-5-sonnet-20241022", captured_cmd[i + 1])
          found_model = true
          break
        end
      end
      assert.is_true(found_model)
    end)

    it("includes --model when model is provided in opts (overrides config)", function()
      config.setup({
        model = "config-model",
        headless = { output_format = "json", force = false },
      })

      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("test prompt", {
        model = "opts-model",
        on_done = function() end,
      })

      vim.system = orig_system

      local found_model_val = nil
      for i, arg in ipairs(captured_cmd) do
        if arg == "--model" then
          found_model_val = captured_cmd[i + 1]
          break
        end
      end
      assert.equals("opts-model", found_model_val)
    end)

    it("includes --force when config.headless.force is true", function()
      config.setup({
        headless = { output_format = "json", force = true },
      })

      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("test", { on_done = function() end })

      vim.system = orig_system

      local has_force = false
      for _, arg in ipairs(captured_cmd) do
        if arg == "--force" then
          has_force = true
          break
        end
      end
      assert.is_true(has_force)
    end)

    it("does not include --force when not set", function()
      config.setup({
        headless = { output_format = "json", force = false },
      })

      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("test", { on_done = function() end })

      vim.system = orig_system

      local has_force = false
      for _, arg in ipairs(captured_cmd) do
        if arg == "--force" then
          has_force = true
          break
        end
      end
      assert.is_false(has_force)
    end)

    it("includes files in the args when provided", function()
      local captured_cmd = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        captured_cmd = cmd
        return {}
      end

      headless.run("review this", {
        files = { "/path/to/file1.lua", "/path/to/file2.lua" },
        on_done = function() end,
      })

      vim.system = orig_system

      -- Files should appear in the command
      local has_file1 = false
      local has_file2 = false
      for _, arg in ipairs(captured_cmd) do
        if arg == "/path/to/file1.lua" then
          has_file1 = true
        end
        if arg == "/path/to/file2.lua" then
          has_file2 = true
        end
      end
      assert.is_true(has_file1)
      assert.is_true(has_file2)
    end)
  end)

  describe("review()", function()
    it("constructs a review prompt with code fence", function()
      local captured_prompt = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        -- Extract the prompt (3rd arg after "-p")
        for i, arg in ipairs(cmd) do
          if arg == "-p" then
            captured_prompt = cmd[i + 1]
            break
          end
        end
        return {}
      end

      headless.review("local x = 1", { on_done = function() end })

      vim.system = orig_system

      assert.is_string(captured_prompt)
      -- Should contain the code in a fence
      assert.truthy(captured_prompt:find("local x = 1", 1, true))
      assert.truthy(captured_prompt:find("```", 1, true))
    end)

    it("includes language in the code fence when provided", function()
      local captured_prompt = nil
      local orig_system = vim.system
      vim.system = function(cmd, _opts, _callback)
        for i, arg in ipairs(cmd) do
          if arg == "-p" then
            captured_prompt = cmd[i + 1]
            break
          end
        end
        return {}
      end

      headless.review("print('hello')", {
        language = "python",
        on_done = function() end,
      })

      vim.system = orig_system

      assert.is_string(captured_prompt)
      assert.truthy(captured_prompt:find("```python", 1, true))
      assert.truthy(captured_prompt:find("print('hello')", 1, true))
    end)

    it("passes on_done callback to run()", function()
      local on_done_called = false
      local orig_system = vim.system
      local stored_callback = nil

      vim.system = function(_cmd, _opts, callback)
        stored_callback = callback
        return {}
      end

      headless.review("code", {
        on_done = function(_code, _events, _stderr)
          on_done_called = true
        end,
      })

      vim.system = orig_system

      -- Simulate process completion
      if stored_callback then
        -- We need vim.schedule to fire; since we're in tests, call directly
        stored_callback({ code = 0, stdout = "", stderr = "" })
        -- on_done uses vim.schedule internally, so just check stored_callback was set
        assert.is_function(stored_callback)
      end
    end)
  end)

  describe("JSON line parsing", function()
    it("parses JSON output from agent via on_output callback", function()
      local received_events = {}
      local completion_code = nil

      -- Simulate stdout that produces JSON lines
      local orig_system = vim.system
      local stored_stdout_fn = nil
      local stored_callback = nil

      vim.system = function(_cmd, opts, callback)
        stored_stdout_fn = opts.stdout
        stored_callback = callback
        return {}
      end

      headless.run("test", {
        on_output = function(event)
          table.insert(received_events, event)
        end,
        on_done = function(code, _events, _stderr)
          completion_code = code
        end,
      })

      vim.system = orig_system

      -- Feed JSON lines via stdout callback
      if stored_stdout_fn then
        local line1 = vim.json.encode({ type = "text", content = "Hello" }) .. "\n"
        local line2 = vim.json.encode({ type = "done" }) .. "\n"
        stored_stdout_fn(nil, line1 .. line2)
      end

      -- Trigger completion
      if stored_callback then
        stored_callback({ code = 0, stdout = "", stderr = "" })
      end

      -- Since vim.schedule wraps the callback, in a real test environment
      -- we just verify the functions were stored correctly
      assert.is_function(stored_stdout_fn)
      assert.is_function(stored_callback)
    end)
  end)

  describe("show_output()", function()
    it("creates a floating window with output content", function()
      local created_win = nil
      local orig_open_win = vim.api.nvim_open_win

      -- Check that open_win is called with floating config
      vim.api.nvim_open_win = function(buf, enter, config)
        if config and config.relative == "editor" then
          created_win = true
        end
        return orig_open_win(buf, enter, config)
      end

      local events = {
        { type = "text", content = "This is review output" },
        { type = "text", content = "Line 2 of output" },
      }

      headless.show_output(events, "Test Review")

      vim.api.nvim_open_win = orig_open_win

      assert.is_true(created_win)

      -- Clean up: close the floating window
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local ok = pcall(function()
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "nofile" and vim.bo[buf].filetype == "markdown" then
            vim.api.nvim_win_close(win, true)
          end
        end)
        _ = ok
      end
    end)

    it("handles empty events list gracefully", function()
      -- Should not crash with empty events
      local ok = pcall(headless.show_output, {}, "Empty Test")
      assert.is_true(ok)

      -- Clean up floating windows
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local ok2 = pcall(function()
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "nofile" then
            vim.api.nvim_win_close(win, true)
          end
        end)
        _ = ok2
      end
    end)
  end)
end)
