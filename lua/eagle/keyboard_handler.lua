local util = require('eagle.util')
local config = require('eagle.config')

local M = {}

-- Function for keyboard-driven rendering (no delays, no mouse checks)
function M.render_keyboard_mode()
    if util.eagle_win and vim.api.nvim_win_is_valid(util.eagle_win) and vim.api.nvim_get_current_win() ~= util.eagle_win then
        vim.api.nvim_set_current_win(util.eagle_win)
        return
    end
    util.load_diagnostics(true)

    if config.options.show_lsp_info then
        util.load_lsp_info(true, function()
            if #util.diagnostic_messages == 0 and #util.lsp_info == 0 then
                return
            end
            util.create_eagle_win(true)
        end)
    else
        if #util.diagnostic_messages == 0 then
            return
        end
        util.create_eagle_win(true)
    end
end

-- Function to show all diagnostics on the current line (no LSP info)
function M.render_line_diagnostics()
  if
    util.eagle_win
    and vim.api.nvim_win_is_valid(util.eagle_win)
    and vim.api.nvim_get_current_win() ~= util.eagle_win
  then
    vim.api.nvim_set_current_win(util.eagle_win)
    return
  end

  -- Get current line number (0-indexed)
  local cursor_pos = vim.fn.getcurpos()
  local current_line = cursor_pos[2] - 1

  local line_diagnostics = vim.diagnostic.get(0, { lnum = current_line })

  if #line_diagnostics == 0 then
    return
  end

  -- Set diagnostic_messages to all diagnostics on the line
  util.diagnostic_messages = line_diagnostics
  util.lsp_info = {}

  util.create_eagle_win(true)
end

return M
