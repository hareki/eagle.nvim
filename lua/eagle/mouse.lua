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
---Snapshot taken when the render countdown started: the getmousepos() result
---and the symbol region under it.
---@type { mpos: table, region: table }?
local captured
---Signature of the diagnostics currently (or last) shown. While it matches,
---renders are skipped, so a manually closed float stays closed until the
---mouse leaves the symbol it was opened on.
---@type table?
local last_sig
---Symbol region the float was opened on. See symbol_region().
---@type table?
local shown_region

---Extent of the symbol under the mouse: 'iskeyword' characters of the hovered
---buffer group into one symbol, any other non-blank character is a symbol of
---its own, and blanks or off-text positions yield nil. first/last are 1-based
---byte bounds spanning whole (possibly multibyte) characters. Leaving this
---region closes the float and re-arms rendering (replaces upstream's
---check_char heuristic).
---@param mpos table getmousepos() result
---@return { win: integer, row: integer, first: integer, last: integer }?
local function symbol_region(mpos)
  -- line/column are 0 over statuslines, separators, and float borders
  if mpos.winid == 0 or mpos.line == 0 or mpos.column == 0 or (mpos.coladd or 0) > 0 then
    return nil
  end
  -- over the number/sign/fold columns getmousepos() clamps column to the
  -- first text byte; reject those cells via the text offset instead
  if mpos.wincol <= vim.fn.getwininfo(mpos.winid)[1].textoff then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(mpos.winid)
  local row = mpos.line - 1
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local first = mpos.column
  if first > #line then
    return nil
  end
  local last = first + vim.str_utf_end(line, first)
  local char = line:sub(first, last)
  if char:match("^%s") then
    return nil
  end
  -- \k reads 'iskeyword' from the current buffer, so classify inside buf
  return vim.api.nvim_buf_call(buf, function()
    if vim.fn.match(char, "^\\k") ~= 0 then
      return { win = mpos.winid, row = row, first = first, last = last }
    end
    local kw_first = vim.fn.match(line:sub(1, last), "\\k\\+$") + 1
    local kw_last = vim.fn.matchend(line, "\\k\\+", first - 1)
    return { win = mpos.winid, row = row, first = kw_first, last = kw_last }
  end)
end

local function reset()
  last_sig = nil
  shown_region = nil
end

---@param diags vim.Diagnostic[]
---@param sections string[][]
---@param sig table
---@param region table
local function open_float(diags, sections, sig, region)
  if #diags == 0 and #sections == 0 then
    return
  end
  local render_above = window.render_above("mouse")
  local result = render.compose({ diagnostics = diags, hover = sections }, { render_above = render_above })
  window.open(result, { anchor = "mouse", render_above = render_above })
  last_sig = sig
  shown_region = region
end

---Whether the mouse still sits where the countdown started. Also compares
---winid, so a stale snapshot never dereferences a window that was closed or
---covered while waiting.
---@param mpos table the captured getmousepos() result
---@return boolean
local function mouse_still_at(mpos)
  local now = vim.fn.getmousepos()
  return now.screenrow == mpos.screenrow and now.screencol == mpos.screencol and now.winid == mpos.winid
end

local function do_render()
  if not captured then
    return
  end
  local mpos, region = captured.mpos, captured.region
  if not mouse_still_at(mpos) or vim.fn.mode() ~= "n" then
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
      -- the mouse may sit still while the request is in flight, but the mode
      -- can change under it (e.g. `i`), so both must be re-checked
      if not mouse_still_at(mpos) or vim.fn.mode() ~= "n" then
        return
      end
      open_float(diags, sections, sig, region)
    end)
  else
    open_float(diags, {}, sig, region)
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
  local region = symbol_region(mpos)
  if not region then
    return
  end
  captured = { mpos = mpos, region = region }
  render_timer:stop()
  render_timer:start(config.options.mouse.render_delay, 0, vim.schedule_wrap(do_render))
end

local function on_move()
  if not idle_timer then
    return
  end
  local mpos = vim.fn.getmousepos()

  if window.is_open() then
    if window.contains(mpos) then
      -- only mouse-opened floats (shown_region set) auto-focus on hover, so
      -- a float opened by :EagleWin cannot steal focus from an idle mouse
      if shown_region and not window.is_focused() then
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
      -- keep the float when it is the focused window, so its text can be
      -- visual-selected and yanked
      if window.is_focused() then
        return
      end
      window.close()
      reset()
    end,
  })

  -- Event-driven replacement for upstream's scroll polling: close on scroll,
  -- then let the idle timer re-render against the new content. A mouse-opened
  -- float only cares about the window it was opened over; scrolls in other
  -- windows (streaming terminals, companion plugins' floats) are ignored.
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    callback = function(ev)
      local scrolled = tonumber(ev.match)
      if scrolled == window.win() then
        return
      end
      if shown_region and scrolled ~= shown_region.win then
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

---Forget the shown-content memory so the next idle render starts fresh. For
---close paths that change what the float would display (e.g. toggling
---headers); without this, do_render keeps skipping while the diagnostics
---under the unmoved mouse still match the remembered signature.
function M.reset()
  reset()
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
