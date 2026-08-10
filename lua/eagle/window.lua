local config = require("eagle.config")
local log = require("eagle.log")
local render = require("eagle.render")

local M = {}

local ns = vim.api.nvim_create_namespace("eagle/render")

---@class eagle.WindowState
---@field win integer?
---@field buf integer?
local state = {
  win = nil,
  buf = nil,
}

local WINHIGHLIGHT = "NormalFloat:EagleNormal,FloatBorder:EagleBorder,FloatTitle:EagleTitle"

---Define the eagle highlight groups as default links, so user overrides win.
---Re-run on ColorScheme, which clears them.
function M.setup_highlights()
  local groups = {
    EagleNormal = "NormalFloat",
    EagleBorder = "FloatBorder",
    EagleTitle = "FloatTitle",
  }
  for name, link in pairs(groups) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

---@return integer buf
local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  local ok, err = pcall(vim.treesitter.start, buf, "markdown")
  if not ok then
    log.warn("markdown treesitter unavailable: %s", err)
  end
  state.buf = buf
  return buf
end

---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---@return integer? win
function M.win()
  return M.is_open() and state.win or nil
end

---@return boolean
function M.is_focused()
  return M.is_open() and vim.api.nvim_get_current_win() == state.win
end

function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
    vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
  end
end

function M.close()
  if M.is_open() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
end

---Whether the mouse is over the float, border included. Border (and shadow)
---cells belong to the float's grid, so getmousepos() reports the float's
---winid for them; this stays correct for every border style, unlike screen
---coordinate math.
---@param mpos table getmousepos() result
---@return boolean
function M.contains(mpos)
  return M.is_open() and mpos.winid == state.win
end

---Screen position of the anchor point (1-based).
---@param anchor "mouse"|"cursor"
---@return integer screenrow
---@return integer screencol
local function anchor_screenpos(anchor)
  if anchor == "mouse" then
    local mpos = vim.fn.getmousepos()
    return mpos.screenrow, mpos.screencol
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(0, cursor[1], cursor[2] + 1)
  return pos.row, pos.col
end

---Whether the float should open above the anchor, based on its screen row.
---@param anchor "mouse"|"cursor"
---@return boolean
function M.render_above(anchor)
  return anchor_screenpos(anchor) > math.floor(vim.o.lines / 2)
end

---@param result eagle.RenderResult
---@return integer width
local function compute_width(result)
  local opts = config.options.window
  local content_width = 0
  for _, line in ipairs(result.lines) do
    if line ~= render.SEPARATOR then
      content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
    end
  end
  -- +2: the 1-space left pad plus one spare cell so links stay clickable
  local max_width = math.min(opts.max_width(), vim.o.columns - 4)
  return math.max(
    math.min(content_width + 2 + opts.scrollbar_offset, max_width),
    math.min(vim.fn.strdisplaywidth(opts.title), vim.o.columns - 4),
    1
  )
end

---Rows the border adds above and below the content. A side is drawn iff its
---edge char is non-empty; char lists repeat cyclically to fill the 8 slots
---(:h nvim_open_win), and empty corner slots add nothing. "shadow" only pads
---the bottom and right.
---@return integer rows
local function border_rows()
  local border = config.options.window.border
  if type(border) == "string" then
    if border == "none" then
      return 0
    end
    return border == "shadow" and 1 or 2
  end
  local rows = 0
  for _, slot in ipairs({ 2, 6 }) do -- top and bottom edge slots, clockwise from top-left
    local char = border[(slot - 1) % #border + 1]
    if type(char) == "table" then
      char = char[1]
    end
    if char ~= "" then
      rows = rows + 1
    end
  end
  return rows
end

---@class eagle.OpenOpts
---@field anchor "mouse"|"cursor"
---@field render_above boolean

---Open the float, or update it in place when it is already visible.
---@param result eagle.RenderResult
---@param opts eagle.OpenOpts
---@return integer? win
function M.open(result, opts)
  local win_opts = config.options.window
  local buf = ensure_buf()

  local width = compute_width(result)
  local lines = render.finalize(result, width - 1 - win_opts.scrollbar_offset)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(result.marks) do
    vim.hl.range(buf, ns, mark.hl, { mark.line, 0 }, { mark.line, -1 }, { priority = vim.hl.priorities.user })
  end

  local has_title = win_opts.title ~= ""
  ---@type vim.api.keyset.win_config
  local win_config = {
    relative = opts.anchor,
    width = width,
    height = 1,
    row = 0,
    col = 0,
    hide = true,
    style = "minimal",
    border = win_opts.border,
    focusable = true,
    title = has_title and win_opts.title or nil,
    title_pos = has_title and win_opts.title_pos or nil,
  }

  local created = false
  if M.is_open() then
    vim.api.nvim_win_set_config(state.win, win_config)
  else
    state.win = vim.api.nvim_open_win(buf, false, win_config)
    created = true

    local window_options = {
      wrap = true,
      linebreak = true,
      breakindent = true,
      conceallevel = config.options.render.conceallevel,
      concealcursor = config.options.render.concealcursor,
      winhighlight = WINHIGHLIGHT,
    }
    for name, value in pairs(window_options) do
      vim.api.nvim_set_option_value(name, value, { win = state.win })
    end

    -- The single point where close is observed, whoever closes the window.
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(state.win),
      once = true,
      callback = function()
        state.win = nil
      end,
    })
  end

  -- Measure the wrapped (and conceal-aware) display height, then position. The
  -- measurement only sees concealment that exists by now, i.e. treesitter
  -- @conceal; a renderer that hides fence lines from a decoration provider draws
  -- after this, so those rows are compensated for by config instead.
  local hidden = result.fences * config.options.render.concealed_fence_rows
  local text_height = vim.api.nvim_win_text_height(state.win, {}).all - hidden
  local max_height = math.min(win_opts.max_height(), vim.o.lines - 4)
  local height = math.max(math.min(text_height, max_height), 1)
  local _, anchor_col = anchor_screenpos(opts.anchor)
  win_config.height = height
  win_config.row = opts.render_above and -(height + border_rows() + win_opts.row_offset) or win_opts.row_offset
  -- clamp the left shift so the float never clips off the screen edge
  win_config.col = -math.min(win_opts.col_offset, math.max(anchor_col - 1, 0))
  win_config.hide = false
  vim.api.nvim_win_set_config(state.win, win_config)

  if created and config.options.on_open then
    config.options.on_open(state.win, buf)
  end
  return state.win
end

return M
