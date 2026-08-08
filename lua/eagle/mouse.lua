local config = require("eagle.config")
local diagnostics = require("eagle.diagnostics")
local log = require("eagle.log")
local lsp = require("eagle.lsp")
local render = require("eagle.render")
local window = require("eagle.window")

local M = {}

local ns = vim.api.nvim_create_namespace("eagle/mouse")
local MOUSEMOVE = vim.keycode("<MouseMove>")

---@type uv.uv_timer_t?
local idle_timer
---@type uv.uv_timer_t?
local render_timer
---One scheduled on_move at a time; coalesces bursts of <MouseMove> keys.
local move_pending = false
---getmousepos() snapshot taken when the render countdown started.
---@type table?
local captured
---Signature of the diagnostics currently (or last) shown. While it matches,
---renders are skipped, so a manually closed float stays closed until the
---mouse leaves the symbol it was opened on.
---@type table?
local last_sig
---Symbol region the float was opened on. See symbol_region().
---@type table?
local shown_region

---Extent of the symbol under the mouse: word characters group into one
---symbol, any other non-blank character is a symbol of its own, and blanks
---or off-text positions yield nil. Leaving this region closes the float and
---re-arms rendering (replaces upstream's check_char heuristic).
---@param mpos table getmousepos() result
---@return { win: integer, row: integer, first: integer, last: integer }?
local function symbol_region(mpos)
  if mpos.winid == 0 or (mpos.coladd or 0) > 0 then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(mpos.winid)
  local row = mpos.line - 1
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local col = mpos.column
  if col > #line then
    return nil
  end
  local char = line:sub(col, col)
  if char:match("%s") then
    return nil
  end
  if not char:match("[%w_]") then
    return { win = mpos.winid, row = row, first = col, last = col }
  end
  local first, last = col, col
  while first > 1 and line:sub(first - 1, first - 1):match("[%w_]") do
    first = first - 1
  end
  while last < #line and line:sub(last + 1, last + 1):match("[%w_]") do
    last = last + 1
  end
  return { win = mpos.winid, row = row, first = first, last = last }
end

local function reset()
  last_sig = nil
  shown_region = nil
end

---@param diags vim.Diagnostic[]
---@param sections string[][]
---@param sig table
---@param mpos table
local function open_float(diags, sections, sig, mpos)
  if #diags == 0 and #sections == 0 then
    return
  end
  local render_above = window.render_above("mouse")
  local result = render.compose({ diagnostics = diags, hover = sections }, { render_above = render_above })
  window.open(result, { anchor = "mouse", render_above = render_above })
  last_sig = sig
  shown_region = symbol_region(mpos)
end

local function do_render()
  if not captured then
    return
  end
  local mpos = vim.fn.getmousepos()
  if mpos.screenrow ~= captured.screenrow or mpos.screencol ~= captured.screencol then
    return
  end
  if vim.fn.mode() ~= "n" then
    return
  end

  local buf = vim.api.nvim_win_get_buf(mpos.winid)
  local pos = { row = mpos.line - 1, col = mpos.column - 1 }
  local diags = diagnostics.at(buf, pos)
  local sig = diagnostics.signature(diags)
  if last_sig and vim.deep_equal(sig, last_sig) then
    return
  end

  local show_lsp = config.options.show_lsp_info and lsp.has_hover(buf)
  if #diags == 0 and not show_lsp then
    return
  end
  log.debug("rendering at %d:%d (%d diagnostics)", pos.row, pos.col, #diags)

  if show_lsp then
    lsp.hover(buf, pos, function(sections)
      local now = vim.fn.getmousepos()
      if now.screenrow ~= mpos.screenrow or now.screencol ~= mpos.screencol then
        return
      end
      open_float(diags, sections, sig, mpos)
    end)
  else
    open_float(diags, {}, sig, mpos)
  end
end

local function on_idle()
  if not render_timer or vim.fn.mode() ~= "n" then
    return
  end
  local mpos = vim.fn.getmousepos()
  if mpos.winid == 0 or mpos.winid == window.win() then
    return
  end
  if not symbol_region(mpos) then
    return
  end
  captured = mpos
  render_timer:stop()
  render_timer:start(config.options.mouse.render_delay, 0, vim.schedule_wrap(do_render))
end

local function on_move()
  if not idle_timer then
    return
  end
  local mpos = vim.fn.getmousepos()

  if window.is_open() then
    if window.contains(mpos.screenrow, mpos.screencol) then
      if not window.is_focused() then
        window.focus()
      end
      return
    end
    if shown_region and not vim.deep_equal(symbol_region(mpos), shown_region) then
      window.close()
      reset()
    end
  elseif shown_region and not vim.deep_equal(symbol_region(mpos), shown_region) then
    reset()
  end

  idle_timer:stop()
  idle_timer:start(config.options.mouse.idle_delay, 0, vim.schedule_wrap(on_idle))
end

---@param augroup integer
function M.enable(augroup)
  vim.o.mousemoveevent = true
  idle_timer = assert(vim.uv.new_timer())
  render_timer = assert(vim.uv.new_timer())

  vim.on_key(function(key, typed)
    if key ~= MOUSEMOVE and typed ~= MOUSEMOVE then
      return
    end
    if move_pending then
      return
    end
    move_pending = true
    vim.schedule(function()
      move_pending = false
      on_move()
    end)
  end, ns)

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    pattern = "n:*",
    callback = function()
      window.close()
      reset()
    end,
  })

  -- Event-driven replacement for upstream's scroll polling: close on scroll,
  -- then let the idle timer re-render against the new content.
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    callback = function(ev)
      if tonumber(ev.match) == window.win() then
        return
      end
      window.close()
      reset()
      if idle_timer then
        idle_timer:stop()
        idle_timer:start(config.options.mouse.idle_delay, 0, vim.schedule_wrap(on_idle))
      end
    end,
  })
end

---Tear down every mouse side effect. Autocmds die with the eagle augroup;
---vim.o.mousemoveevent is deliberately left as-is, since other plugins may
---rely on it.
function M.disable()
  vim.on_key(nil, ns)
  for _, timer in ipairs({ idle_timer, render_timer }) do
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  idle_timer = nil
  render_timer = nil
  captured = nil
  move_pending = false
  reset()
  log.debug("mouse handling disabled")
end

return M
