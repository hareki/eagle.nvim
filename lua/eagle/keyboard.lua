local config = require("eagle.config")
local diagnostics = require("eagle.diagnostics")
local lsp = require("eagle.lsp")
local render = require("eagle.render")
local window = require("eagle.window")

local M = {}

---Shared open/focus/close cycle: an open unfocused float gets focused, a
---focused one gets closed, otherwise build fresh content.
---@param build fun()
local function toggle_or(build)
  if window.is_open() then
    if window.is_focused() then
      window.close()
    else
      window.focus()
    end
    return
  end
  build()
end

---@param diags vim.Diagnostic[]
---@param sections string[][]
local function open_float(diags, sections)
  if #diags == 0 and #sections == 0 then
    return
  end
  local render_above = window.render_above("cursor")
  local result = render.compose({ diagnostics = diags, hover = sections }, { render_above = render_above })
  window.open(result, { anchor = "cursor", render_above = render_above })
end

---:EagleWin - diagnostics under the cursor plus LSP hover info.
function M.show()
  toggle_or(function()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local pos = { row = cursor[1] - 1, col = cursor[2] }
    local diags = diagnostics.at(buf, pos)
    if config.options.show_lsp_info and lsp.has_hover(buf) then
      lsp.hover(buf, pos, function(sections)
        -- drop the response if the window, buffer, or cursor changed while
        -- the request was in flight (the float anchors to the current cursor)
        if
          vim.api.nvim_get_current_win() ~= win
          or vim.api.nvim_get_current_buf() ~= buf
          or not vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor)
        then
          return
        end
        open_float(diags, sections)
      end)
    else
      open_float(diags, {})
    end
  end)
end

---:EagleWinLineDiagnostic - every diagnostic on the cursor line, regardless
---of column, with LSP hover suppressed.
function M.show_line()
  toggle_or(function()
    local buf = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    open_float(diagnostics.on_line(buf, row), {})
  end)
end

function M.enable()
  vim.api.nvim_create_user_command("EagleWin", M.show, {})
  vim.api.nvim_create_user_command("EagleWinLineDiagnostic", M.show_line, {})
end

return M
