--- lua/cursoragent/headless.lua
--- Wraps "agent -p <prompt> --output-format json" for headless operation

local M = {}

local logger = require("cursoragent.logger")

---@param prompt string
---@param opts table { files?, model?, force?, output_format? }
---@return string[]
local function build_args(prompt, opts)
  local config = require("cursoragent.config")
  local agent_cmd = config.get_agent_cmd()
  local args = { agent_cmd, "-p", prompt }

  local output_format = opts.output_format or config.values.headless.output_format or "json"
  vim.list_extend(args, { "--output-format", output_format })

  if opts.force or config.values.headless.force then
    table.insert(args, "--force")
  end

  local model = opts.model or config.values.model
  if model then
    vim.list_extend(args, { "--model", model })
  end

  if opts.files and #opts.files > 0 then
    vim.list_extend(args, opts.files)
  end

  return args
end

--- Run agent in headless mode.
---@param prompt string
---@param opts table { files?, model?, force?, output_format?, cwd?, on_output?, on_done? }
function M.run(prompt, opts)
  opts = opts or {}

  local args = build_args(prompt, opts)
  logger.debug("headless run: %s", table.concat(args, " "))

  local stdout_buf = ""
  local stderr_buf = ""
  local output_format = opts.output_format
    or require("cursoragent.config").values.headless.output_format
    or "json"

  local sys_opts = {
    stdout = function(_err, data)
      if data then
        stdout_buf = stdout_buf .. data
      end
    end,
    stderr = function(_err, data)
      if data then
        stderr_buf = stderr_buf .. data
      end
    end,
  }
  if opts.cwd then
    sys_opts.cwd = opts.cwd
  end

  vim.system(args, sys_opts, function(completed)
    vim.schedule(function()
      if completed.code ~= 0 then
        logger.error("headless agent exited %d: %s", completed.code, stderr_buf)
        if opts.on_done then
          opts.on_done(completed.code, nil, stderr_buf)
        end
        return
      end

      local events = {}

      if output_format == "json" or output_format == "stream-json" then
        for line in (stdout_buf .. "\n"):gmatch("([^\n]*)\n") do
          line = vim.trim(line)
          if line ~= "" then
            local ok, parsed = pcall(vim.json.decode, line)
            if ok and type(parsed) == "table" then
              table.insert(events, parsed)
              if opts.on_output then
                opts.on_output(parsed)
              end
            end
          end
        end
      else
        local ev = { type = "text", content = stdout_buf }
        table.insert(events, ev)
        if opts.on_output then
          opts.on_output(ev)
        end
      end

      if opts.on_done then
        opts.on_done(completed.code, events, stderr_buf)
      end
    end)
  end)
end

--- Review a code snippet or visual selection.
---@param text string code to review
---@param opts table { language?, on_output?, on_done?, files? }
function M.review(text, opts)
  opts = opts or {}
  local lang = opts.language or ""
  local fence = lang ~= "" and ("```" .. lang) or "```"
  local prompt = string.format("Review this code and provide concise feedback:\n\n%s\n%s\n```", fence, text)
  M.run(prompt, opts)
end

--- Show headless output in a floating scratch buffer.
---@param events table[]
---@param title string|nil
function M.show_output(events, title)
  local lines = {}
  for _, ev in ipairs(events) do
    local ev_type = ev.type or ev.event or ""
    local content = ev.content or ev.text or ev.result or ev.output or ""
    if type(content) == "string" and content ~= "" then
      -- Only include text/content/result types
      if ev_type == "" or ev_type == "text" or ev_type == "content" or ev_type == "result" then
        for _, l in ipairs(vim.split(content, "\n")) do
          table.insert(lines, l)
        end
      end
    end
  end

  if #lines == 0 then
    table.insert(lines, "(no output)")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "markdown"

  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(40, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. (title or "cursoragent") .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = true

  local map_opts = { noremap = true, silent = true, buffer = buf }
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, map_opts)
  end
end

return M
