--- plugin/cursoragent.lua
--- Entry point for cursoragent.nvim
--- Loaded automatically by Neovim's plugin system

-- Guard against double-loading
if vim.g.loaded_cursoragent then
  return
end
vim.g.loaded_cursoragent = true

-- Require Neovim >= 0.10
if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify(
    "[cursoragent] Neovim >= 0.10 is required (you have " .. tostring(vim.version()) .. ")",
    vim.log.levels.ERROR
  )
  return
end

-- Set up with defaults if the user hasn't called setup() themselves.
-- This ensures commands are always registered even for users who skip setup().
-- Uses vim.schedule to run after all plugins have loaded.
vim.schedule(function()
  local ok, cursoragent = pcall(require, "cursoragent")
  if not ok then
    vim.notify("[cursoragent] Failed to load: " .. tostring(cursoragent), vim.log.levels.ERROR)
    return
  end

  if not cursoragent.is_initialized() then
    cursoragent.setup_defaults()
  end
end)
