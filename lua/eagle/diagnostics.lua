local config = require("eagle.config")

local M = {}

---@class eagle.Pos
---@field row integer 0-indexed buffer row
---@field col integer 0-indexed byte column

---Effective end of a diagnostic range, with fallbacks for missing fields and
---zero-width ranges (which still draw an underline and must stay hittable).
---@param d vim.Diagnostic
---@return integer end_lnum
---@return integer end_col
local function range_end(d)
  local end_lnum = d.end_lnum or d.lnum
  local end_col = d.end_col or d.col
  if end_lnum == d.lnum and end_col <= d.col then
    end_col = d.col + 1
  end
  return end_lnum, end_col
end

---@param d vim.Diagnostic
---@param pos eagle.Pos
---@return boolean
local function contains(d, pos)
  local end_lnum, end_col = range_end(d)
  if pos.row < d.lnum or pos.row > end_lnum then
    return false
  end
  if pos.row == d.lnum and pos.col < d.col then
    return false
  end
  if pos.row == end_lnum and pos.col >= end_col then
    return false
  end
  return true
end

---Apply the user's diagnostic_filter, then order by severity (stable).
---@param diags vim.Diagnostic[]
---@return vim.Diagnostic[]
local function refine(diags)
  local filter = config.options.diagnostic_filter
  if filter then
    diags = vim.tbl_filter(filter, diags)
  end
  local index = {}
  for i, d in ipairs(diags) do
    index[d] = i
  end
  table.sort(diags, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    return index[a] < index[b]
  end)
  return diags
end

---Diagnostics whose range contains pos, filtered and sorted by severity.
---@param buf integer
---@param pos eagle.Pos
---@return vim.Diagnostic[]
function M.at(buf, pos)
  return refine(vim.tbl_filter(function(d)
    return contains(d, pos)
  end, vim.diagnostic.get(buf, { lnum = pos.row })))
end

---All diagnostics on a line regardless of column, filtered and sorted by severity.
---@param buf integer
---@param row integer 0-indexed buffer row
---@return vim.Diagnostic[]
function M.on_line(buf, row)
  return refine(vim.diagnostic.get(buf, { lnum = row }))
end

---Stable projection of a diagnostic list, compared with vim.deep_equal to
---decide whether the currently displayed content is already up to date.
---@param diags vim.Diagnostic[]
---@return table
function M.signature(diags)
  local sig = {}
  for i, d in ipairs(diags) do
    sig[i] = { d.lnum, d.col, d.end_lnum, d.end_col, d.severity, d.message, d.source, d.code }
  end
  return sig
end

return M
