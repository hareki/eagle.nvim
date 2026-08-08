local config = require("eagle.config")

local M = {}

local COMMANDS = { "EagleWin", "EagleWinLineDiagnostic", "EagleWinToggleHeaders" }

local ignore_cursor_move = false

---Suppress the next CursorMoved auto-close. For external code that moves the
---cursor or switches windows programmatically (e.g. focus keymaps); noautocmd
---cannot suppress CursorMoved (vim/vim#2084).
function M.ignore_next_cursor_move()
  ignore_cursor_move = true
end

---@return boolean
function M.is_open()
  return require("eagle.window").is_open()
end

function M.close()
  require("eagle.window").close()
end

---Toggle the "# Diagnostics" / "# LSP Info" headers and close the float so
---the next render picks the change up.
---@return boolean shown
function M.toggle_headers()
  config.options.show_headers = not config.options.show_headers
  require("eagle.window").close()
  return config.options.show_headers
end

---@param opts eagle.Config|table|nil
function M.setup(opts)
  config.setup(opts)

  -- Tear down anything a previous setup() registered, making re-setup safe.
  if package.loaded["eagle.mouse"] then
    require("eagle.mouse").disable()
  end
  for _, command in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, command)
  end
  local augroup = vim.api.nvim_create_augroup("eagle", { clear = true })

  local o = config.options
  if not o.mouse.enabled and not o.keyboard.enabled then
    return
  end

  local window = require("eagle.window")
  window.setup_highlights()

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = window.setup_highlights,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    nested = true,
    callback = function()
      if ignore_cursor_move then
        ignore_cursor_move = false
        return
      end
      if window.is_open() and not window.is_focused() then
        window.close()
      end
    end,
  })

  if o.close_on_cmd then
    vim.api.nvim_create_autocmd("CmdlineEnter", {
      group = augroup,
      callback = function()
        window.close()
      end,
    })
  end

  if o.mouse.enabled then
    require("eagle.mouse").enable(augroup)
  end
  if o.keyboard.enabled then
    require("eagle.keyboard").enable()
  end

  vim.api.nvim_create_user_command("EagleWinToggleHeaders", function()
    M.toggle_headers()
  end, {})
end

return M
