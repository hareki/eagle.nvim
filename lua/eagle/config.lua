local M = {}

---@class eagle.SeverityStyle
---@field icon string Prefix shown before the callout title text.
---@field hl string Highlight group applied to the whole title line.

---@class eagle.MouseOpts
---@field enabled boolean Enable mouse tracking. When false, eagle registers no
---mouse side effects at all: no key observer, no timers, no mouse autocmds,
---and vim.o.mousemoveevent is left untouched.
---@field render_delay integer ms the mouse must rest on a spot before the float opens.
---@field idle_delay integer ms without mouse movement before the mouse counts as idle.

---@class eagle.KeyboardOpts
---@field enabled boolean Register :EagleWin and :EagleWinLineDiagnostic.

---@class eagle.RenderOpts
---@field severity table<"ERROR"|"WARN"|"INFO"|"HINT", eagle.SeverityStyle>
---@field expand_separators boolean Expand separators to full-width "─" rules.
---@field unescape boolean Strip LSP-server backslash over-escaping outside code.
---@field conceallevel integer Applied to the eagle window only.
---@field concealcursor string Applied to the eagle window only.

---@class eagle.WindowOpts
---@field border string|string[] See :h nvim_open_win.
---@field title string
---@field title_pos "left"|"center"|"right"
---@field row_offset integer Rows between the anchor and the float.
---@field col_offset integer Columns the float is shifted left of the anchor.
---@field scrollbar_offset integer Extra right-side columns for scrollbar plugins.
---@field max_width fun(): integer Re-evaluated on every render.
---@field max_height fun(): integer Re-evaluated on every render.

---@class eagle.Config
---@field mouse eagle.MouseOpts
---@field keyboard eagle.KeyboardOpts
---@field order 1|2|3|4 Section order of diagnostics (D) and LSP info (L).
---Left of the slash is the layout when the float opens above the anchor,
---right when below: 1. DL/DL  2. DL/LD  3. LD/LD  4. LD/DL
---@field show_headers boolean Show the "# Diagnostics" / "# LSP Info" headers.
---@field show_lsp_info boolean Include LSP hover contents in the float.
---@field close_on_cmd boolean Close the float when entering the command line.
---@field logging boolean Debug logging via vim.notify (check :messages).
---@field diagnostic_filter (fun(d: vim.Diagnostic): boolean?)? Applied at
---collection time; rejected diagnostics never influence whether the float opens.
---@field source_formatters table<string, fun(d: vim.Diagnostic): string> Message
---rewriters keyed by diagnostic.source; the returned string may be markdown.
---@field on_open (fun(win: integer, buf: integer))? Runs after the float is created.
---@field render eagle.RenderOpts
---@field window eagle.WindowOpts

---@type eagle.Config
local defaults = {
  mouse = {
    enabled = true,
    render_delay = 500,
    idle_delay = 50,
  },
  keyboard = {
    enabled = false,
  },
  order = 1,
  show_headers = true,
  show_lsp_info = true,
  close_on_cmd = true,
  logging = false,
  diagnostic_filter = nil,
  source_formatters = {},
  on_open = nil,
  render = {
    severity = {
      ERROR = { icon = "󰅚 ", hl = "DiagnosticError" },
      WARN = { icon = "󰀪 ", hl = "DiagnosticWarn" },
      INFO = { icon = "󰋽 ", hl = "DiagnosticInfo" },
      HINT = { icon = "󰌶 ", hl = "DiagnosticHint" },
    },
    expand_separators = true,
    unescape = true,
    conceallevel = 3,
    concealcursor = "nc",
  },
  window = {
    border = "single",
    title = "",
    title_pos = "center",
    row_offset = 1,
    col_offset = 5,
    scrollbar_offset = 0,
    max_width = function()
      return math.floor(vim.o.columns / 2)
    end,
    max_height = function()
      return math.floor(vim.o.lines / 2.5)
    end,
  },
}

---@type eagle.Config
M.options = vim.deepcopy(defaults)

local function validate()
  local o = M.options
  vim.validate("mouse.enabled", o.mouse.enabled, "boolean")
  vim.validate("mouse.render_delay", o.mouse.render_delay, "number")
  vim.validate("mouse.idle_delay", o.mouse.idle_delay, "number")
  vim.validate("keyboard.enabled", o.keyboard.enabled, "boolean")
  vim.validate("order", o.order, function(v)
    return v == 1 or v == 2 or v == 3 or v == 4
  end, "1, 2, 3 or 4")
  vim.validate("show_headers", o.show_headers, "boolean")
  vim.validate("show_lsp_info", o.show_lsp_info, "boolean")
  vim.validate("close_on_cmd", o.close_on_cmd, "boolean")
  vim.validate("logging", o.logging, "boolean")
  vim.validate("diagnostic_filter", o.diagnostic_filter, "callable", true)
  vim.validate("source_formatters", o.source_formatters, "table")
  vim.validate("on_open", o.on_open, "callable", true)
  vim.validate("render.severity", o.render.severity, "table")
  for name, style in pairs(o.render.severity) do
    vim.validate("render.severity." .. name .. ".icon", style.icon, "string")
    vim.validate("render.severity." .. name .. ".hl", style.hl, "string")
  end
  vim.validate("render.expand_separators", o.render.expand_separators, "boolean")
  vim.validate("render.unescape", o.render.unescape, "boolean")
  vim.validate("render.conceallevel", o.render.conceallevel, "number")
  vim.validate("render.concealcursor", o.render.concealcursor, "string")
  vim.validate("window.border", o.window.border, { "string", "table" })
  vim.validate("window.title", o.window.title, "string")
  vim.validate("window.title_pos", o.window.title_pos, "string")
  vim.validate("window.row_offset", o.window.row_offset, "number")
  vim.validate("window.col_offset", o.window.col_offset, "number")
  vim.validate("window.scrollbar_offset", o.window.scrollbar_offset, "number")
  vim.validate("window.max_width", o.window.max_width, "callable")
  vim.validate("window.max_height", o.window.max_height, "callable")

  o.mouse.render_delay = math.max(o.mouse.render_delay, 0)
  o.mouse.idle_delay = math.max(o.mouse.idle_delay, 0)
end

---@param options eagle.Config|table|nil
function M.setup(options)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  validate()
end

return M
