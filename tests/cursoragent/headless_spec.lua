--- tests/cursoragent/headless_spec.lua
--- Tests for lua/cursoragent/headless.lua

-- We need config to be set up before testing headless
local config = require("cursoragent.config")

describe("cursoragent.headless", function()
  local headless

  before_each(function()
    package.loaded["cursoragent.headless"] = nil
    config.setup({})
    headless = require("cursoragent.headless")
  end)

  describe("review()", function()
    it("wraps text in a code fence for the prompt", function()
      local captured_prompt = nil
      local orig_run = headless.run
      headless.run = function(prompt, _opts)
        captured_prompt = prompt
      end

      headless.review("local x = 1", { language = "lua" })

      headless.run = orig_run
      assert.truthy(captured_prompt)
      assert.truthy(captured_prompt:match("```lua"))
      assert.truthy(captured_prompt:match("local x = 1"))
    end)

    it("uses plain fence when no language given", function()
      local captured_prompt = nil
      local orig_run = headless.run
      headless.run = function(prompt, _opts)
        captured_prompt = prompt
      end

      headless.review("some code", {})

      headless.run = orig_run
      assert.truthy(captured_prompt:match("```\n"))
    end)

    it("passes opts through to run()", function()
      local captured_opts = nil
      local orig_run = headless.run
      headless.run = function(_prompt, opts)
        captured_opts = opts
      end

      local on_done_fn = function() end
      headless.review("code", { on_done = on_done_fn, language = "python" })

      headless.run = orig_run
      assert.equals(on_done_fn, captured_opts.on_done)
    end)
  end)

  describe("show_output()", function()
    it("extracts text/content/result event types", function()
      local lines_written = nil
      local orig_create_buf = vim.api.nvim_create_buf
      local orig_set_lines = vim.api.nvim_buf_set_lines
      local orig_open_win = vim.api.nvim_open_win
      local orig_keymap = vim.keymap.set
      local orig_bo = vim.bo

      local fake_buf = 9001
      vim.api.nvim_create_buf = function() return fake_buf end
      vim.api.nvim_buf_set_lines = function(_buf, _s, _e, _strict, lines)
        lines_written = lines
      end
      vim.api.nvim_open_win = function() return 1 end
      vim.keymap.set = function() end
      -- stub vim.bo so filetype assignment doesn't error
      vim.bo = setmetatable({}, {
        __newindex = function() end,
        __index = function() return "" end,
      })
      local orig_wo = vim.wo
      vim.wo = setmetatable({}, {
        __newindex = function() end,
        __index = function() return false end,
      })

      headless.show_output({
        { type = "text", content = "alpha" },
        { type = "content", content = "beta" },
        { type = "result", result = "gamma" },
        { type = "metadata", data = {} }, -- should be ignored (no content string)
      }, "Test")

      vim.api.nvim_create_buf = orig_create_buf
      vim.api.nvim_buf_set_lines = orig_set_lines
      vim.api.nvim_open_win = orig_open_win
      vim.keymap.set = orig_keymap
      vim.bo = orig_bo
      vim.wo = orig_wo

      assert.truthy(lines_written)
      local joined = table.concat(lines_written, "\n")
      assert.truthy(joined:match("alpha"))
      assert.truthy(joined:match("beta"))
      assert.truthy(joined:match("gamma"))
    end)

    it("shows '(no output)' when events are empty", function()
      local lines_written = nil
      local orig_create_buf = vim.api.nvim_create_buf
      local orig_set_lines = vim.api.nvim_buf_set_lines
      local orig_open_win = vim.api.nvim_open_win
      local orig_keymap = vim.keymap.set

      local fake_buf = 9002
      vim.api.nvim_create_buf = function() return fake_buf end
      vim.api.nvim_buf_set_lines = function(_buf, _s, _e, _strict, lines)
        lines_written = lines
      end
      vim.api.nvim_open_win = function() return 1 end
      vim.keymap.set = function() end
      local orig_bo = vim.bo
      vim.bo = setmetatable({}, { __newindex = function() end, __index = function() return "" end })
      local orig_wo = vim.wo
      vim.wo = setmetatable({}, { __newindex = function() end, __index = function() return false end })

      headless.show_output({})

      vim.api.nvim_create_buf = orig_create_buf
      vim.api.nvim_buf_set_lines = orig_set_lines
      vim.api.nvim_open_win = orig_open_win
      vim.keymap.set = orig_keymap
      vim.bo = orig_bo
      vim.wo = orig_wo

      assert.truthy(lines_written)
      assert.truthy(table.concat(lines_written, ""):match("%(no output%)"))
    end)
  end)
end)
