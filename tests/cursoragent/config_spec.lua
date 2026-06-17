--- tests/cursoragent/config_spec.lua
--- Tests for lua/cursoragent/config.lua

local config = require("cursoragent.config")

describe("cursoragent.config", function()
  before_each(function()
    -- Reset config to defaults before each test
    config.setup(nil)
  end)

  describe("defaults", function()
    it("has mode = 'acp'", function()
      assert.equals("acp", config.values.mode)
    end)

    it("has agent_cmd = nil (falls back to 'agent')", function()
      assert.is_nil(config.values.agent_cmd)
    end)

    it("get_agent_cmd returns 'agent' when agent_cmd is nil", function()
      assert.equals("agent", config.get_agent_cmd())
    end)

    it("has auto_start = true", function()
      assert.is_true(config.values.auto_start)
    end)

    it("has log_level = 'info'", function()
      assert.equals("info", config.values.log_level)
    end)

    it("has acp.auto_authenticate = true", function()
      assert.is_true(config.values.acp.auto_authenticate)
    end)

    it("has acp.permission.mode = 'ask'", function()
      assert.equals("ask", config.values.acp.permission.mode)
    end)

    it("has headless.output_format = 'json'", function()
      assert.equals("json", config.values.headless.output_format)
    end)

    it("has headless.force = false", function()
      assert.is_false(config.values.headless.force)
    end)

    it("has track_selection = true", function()
      assert.is_true(config.values.track_selection)
    end)

    it("has visual_demotion_delay_ms = 50", function()
      assert.equals(50, config.values.visual_demotion_delay_ms)
    end)

    it("has terminal.split_side = 'right'", function()
      assert.equals("right", config.values.terminal.split_side)
    end)

    it("has terminal.split_width_percentage = 0.30", function()
      assert.equals(0.30, config.values.terminal.split_width_percentage)
    end)

    it("has terminal.provider = 'auto'", function()
      assert.equals("auto", config.values.terminal.provider)
    end)

    it("has terminal.git_repo_cwd = true", function()
      assert.is_true(config.values.terminal.git_repo_cwd)
    end)

    it("has diff_opts.layout = 'vertical'", function()
      assert.equals("vertical", config.values.diff_opts.layout)
    end)
  end)

  describe("setup()", function()
    it("merges user opts over defaults", function()
      config.setup({ mode = "terminal", log_level = "debug" })
      assert.equals("terminal", config.values.mode)
      assert.equals("debug", config.values.log_level)
      -- Other defaults preserved
      assert.is_true(config.values.auto_start)
    end)

    it("deep merges nested opts", function()
      config.setup({ acp = { permission = { mode = "yolo" } } })
      assert.equals("yolo", config.values.acp.permission.mode)
      -- Sibling keys preserved
      assert.is_true(config.values.acp.auto_authenticate)
    end)

    it("sets agent_cmd when provided", function()
      config.setup({ agent_cmd = "cursor-agent" })
      assert.equals("cursor-agent", config.values.agent_cmd)
      assert.equals("cursor-agent", config.get_agent_cmd())
    end)

    it("resets to defaults on each call", function()
      config.setup({ mode = "terminal" })
      assert.equals("terminal", config.values.mode)
      config.setup(nil)
      assert.equals("acp", config.values.mode)
    end)

    it("accepts nil opts without error", function()
      assert.has_no.errors(function()
        config.setup(nil)
      end)
    end)

    it("accepts empty table opts without error", function()
      assert.has_no.errors(function()
        config.setup({})
      end)
    end)
  end)

  describe("validation", function()
    it("rejects invalid mode and falls back to 'acp'", function()
      config.setup({ mode = "invalid_mode" })
      assert.equals("acp", config.values.mode)
    end)

    it("rejects invalid acp.permission.mode and falls back to 'ask'", function()
      config.setup({ acp = { permission = { mode = "auto_destroy" } } })
      assert.equals("ask", config.values.acp.permission.mode)
    end)

    it("rejects invalid terminal.provider and falls back to 'auto'", function()
      config.setup({ terminal = { provider = "tmux" } })
      assert.equals("auto", config.values.terminal.provider)
    end)

    it("rejects invalid headless.output_format and falls back to 'json'", function()
      config.setup({ headless = { output_format = "xml" } })
      assert.equals("json", config.values.headless.output_format)
    end)

    it("rejects split_width_percentage <= 0 and falls back to 0.30", function()
      config.setup({ terminal = { split_width_percentage = 0 } })
      assert.equals(0.30, config.values.terminal.split_width_percentage)
    end)

    it("rejects split_width_percentage >= 1 and falls back to 0.30", function()
      config.setup({ terminal = { split_width_percentage = 1.5 } })
      assert.equals(0.30, config.values.terminal.split_width_percentage)
    end)

    it("accepts valid modes: terminal, headless, acp", function()
      for _, mode in ipairs({ "acp", "headless", "terminal" }) do
        config.setup({ mode = mode })
        assert.equals(mode, config.values.mode)
      end
    end)

    it("accepts valid permission modes", function()
      for _, pm in ipairs({ "ask", "allow_edits", "yolo" }) do
        config.setup({ acp = { permission = { mode = pm } } })
        assert.equals(pm, config.values.acp.permission.mode)
      end
    end)
  end)

  describe("get()", function()
    it("retrieves top-level values", function()
      config.setup({ mode = "headless" })
      assert.equals("headless", config.get("mode"))
    end)

    it("retrieves nested values by dot path", function()
      config.setup({ acp = { permission = { mode = "yolo" } } })
      assert.equals("yolo", config.get("acp.permission.mode"))
    end)

    it("returns nil for unknown keys", function()
      assert.is_nil(config.get("does.not.exist"))
    end)
  end)
end)
