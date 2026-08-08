local config = require("eagle.config")

local M = {}

---Sentinel for a horizontal rule. Written to the buffer as a markdown
---thematic break, or expanded to a full-width "─" rule by M.finalize.
---"___" is used instead of "---" because a "---" line directly after text is
---parsed as a setext H2 underline, silently promoting that text to a heading.
M.SEPARATOR = "___"

---@class eagle.RenderMark
---@field line integer 0-indexed line in the rendered buffer
---@field hl string highlight group for that whole line

---@class eagle.RenderResult
---@field lines string[]
---@field marks eagle.RenderMark[]

---@class eagle.RenderContent
---@field diagnostics vim.Diagnostic[]
---@field hover string[][] one markdown section per LSP client

---@class eagle.RenderContext
---@field render_above boolean whether the float will open above the anchor

local ESCAPED_PUNCT = "\\([%(%)%[%]{}%.%+%-_%*`#!<>])"

---@param segment string
---@return string
local function unescape(segment)
  return (segment:gsub(ESCAPED_PUNCT, "%1"))
end

---Strip backslash over-escaping that LSP servers apply to markdown text,
---leaving inline code spans untouched (they often hold regexes or paths
---where a backslash is meaningful).
---@param line string
---@return string
function M.sanitize_line(line)
  local out = {}
  local i = 1
  while i <= #line do
    local s, e = line:find("`[^`]*`", i)
    if not s then
      out[#out + 1] = unescape(line:sub(i))
      break
    end
    out[#out + 1] = unescape(line:sub(i, s - 1))
    out[#out + 1] = line:sub(s, e)
    i = e + 1
  end
  return table.concat(out)
end

---Append markdown lines to out, rewriting "---" rules to the separator
---sentinel and unescaping prose. Fenced code blocks pass through untouched.
---@param out string[]
---@param lines string[]
local function append_markdown(out, lines)
  local in_fence = false
  for _, line in ipairs(lines) do
    if line:match("^%s*```") then
      in_fence = not in_fence
      out[#out + 1] = line
    elseif in_fence then
      out[#out + 1] = line
    elseif line:match("^%s*%-%-%-+%s*$") then
      out[#out + 1] = M.SEPARATOR
    elseif config.options.render.unescape then
      out[#out + 1] = M.sanitize_line(line)
    else
      out[#out + 1] = line
    end
  end
end

---Severity name and style with safe fallbacks for exotic diagnostics.
---@param severity any
---@return string name
---@return eagle.SeverityStyle style
local function severity_style(severity)
  local name = type(severity) == "number" and vim.diagnostic.severity[severity] or nil
  local style = name and config.options.render.severity[name] or nil
  return name or "DIAGNOSTIC", style or { icon = "", hl = "NormalFloat" }
end

---@param d vim.Diagnostic
---@return string?
local function format_meta(d)
  local code = d.code ~= nil and tostring(d.code) or nil
  if d.source and code then
    return ("%s(%s)"):format(d.source, code)
  end
  return d.source or code
end

---@param diags vim.Diagnostic[]
---@return string[] lines
---@return eagle.RenderMark[] marks 0-indexed within the returned lines
local function diagnostics_block(diags)
  local out = {}
  local marks = {}
  for i, d in ipairs(diags) do
    if i > 1 then
      out[#out + 1] = M.SEPARATOR
    end

    local name, style = severity_style(d.severity)
    marks[#marks + 1] = { line = #out, hl = style.hl }
    out[#out + 1] = style.icon .. (format_meta(d) or name)

    local formatter = d.source and config.options.source_formatters[d.source]
    local message = formatter and formatter(d) or d.message
    append_markdown(out, vim.split(message, "\n", { plain = true, trimempty = true }))

    local href = vim.tbl_get(d, "user_data", "lsp", "codeDescription", "href")
    if href then
      out[#out + 1] = ("[View documents](%s)"):format(href)
    end
  end
  return out, marks
end

---@param sections string[][]
---@return string[]
local function hover_block(sections)
  local out = {}
  for i, section in ipairs(sections) do
    if i > 1 then
      out[#out + 1] = M.SEPARATOR
    end
    append_markdown(out, section)
  end
  return out
end

---Build the eagle buffer content from structured diagnostics and hover data.
---@param content eagle.RenderContent
---@param ctx eagle.RenderContext
---@return eagle.RenderResult
function M.compose(content, ctx)
  local diag_lines, diag_marks = diagnostics_block(content.diagnostics)
  local hover_lines = hover_block(content.hover)

  local order = config.options.order
  local diag_first = order == 1 or (order == 2 and ctx.render_above) or (order == 4 and not ctx.render_above)

  local lines = {}
  local marks = {}

  ---@param block_lines string[]
  ---@param block_marks eagle.RenderMark[]?
  ---@param header string
  local function append_block(block_lines, block_marks, header)
    if #block_lines == 0 then
      return
    end
    if #lines > 0 then
      lines[#lines + 1] = M.SEPARATOR
    end
    if config.options.show_headers then
      lines[#lines + 1] = header
    end
    local offset = #lines
    for _, line in ipairs(block_lines) do
      lines[#lines + 1] = line
    end
    for _, mark in ipairs(block_marks or {}) do
      marks[#marks + 1] = { line = offset + mark.line, hl = mark.hl }
    end
  end

  if diag_first then
    append_block(diag_lines, diag_marks, "# Diagnostics")
    append_block(hover_lines, nil, "# LSP Info")
  else
    append_block(hover_lines, nil, "# LSP Info")
    append_block(diag_lines, diag_marks, "# Diagnostics")
  end

  return { lines = lines, marks = marks }
end

---Expand separator sentinels and apply the 1-space left pad. Line count and
---order are preserved, so marks from M.compose stay valid.
---@param result eagle.RenderResult
---@param rule_width integer display width for expanded separator rules
---@return string[]
function M.finalize(result, rule_width)
  local lines = {}
  for i, line in ipairs(result.lines) do
    if line == M.SEPARATOR and config.options.render.expand_separators then
      line = ("─"):rep(math.max(rule_width, 1))
    end
    lines[i] = " " .. line
  end
  return lines
end

return M
