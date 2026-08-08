local log = require("eagle.log")

local M = {}

---Cancel function for the in-flight hover request, if any.
---@type fun()?
local cancel

---Whether at least one client attached to buf can answer textDocument/hover.
---@param buf integer
---@return boolean
function M.has_hover(buf)
  return #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/hover" }) > 0
end

---@param line string
---@return boolean
local function is_blank(line)
  return line:match("^%s*$") ~= nil or line:match("^%s*%-%-%-+%s*$") ~= nil
end

---Convert one client's hover result into markdown lines.
---Returns nil when the payload has no real content (only blanks or rules).
---@param result lsp.Hover?
---@return string[]?
local function to_section(result)
  if not result or not result.contents then
    return nil
  end
  local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
  local first, last = 1, #lines
  while first <= last and lines[first]:match("^%s*$") do
    first = first + 1
  end
  while last >= first and lines[last]:match("^%s*$") do
    last = last - 1
  end
  local section = {}
  local has_content = false
  for i = first, last do
    section[#section + 1] = lines[i]
    has_content = has_content or not is_blank(lines[i])
  end
  if not has_content then
    return nil
  end
  return section
end

---Request hover at pos from every capable client attached to buf.
---Cancels any previous request still in flight. The callback receives one
---markdown section per client that returned content, in client-id order.
---@param buf integer
---@param pos eagle.Pos
---@param callback fun(sections: string[][])
function M.hover(buf, pos, callback)
  if cancel then
    cancel()
    cancel = nil
  end
  cancel = vim.lsp.buf_request_all(buf, "textDocument/hover", function(client)
    local line = vim.api.nvim_buf_get_lines(buf, pos.row, pos.row + 1, false)[1] or ""
    return {
      textDocument = vim.lsp.util.make_text_document_params(buf),
      position = {
        line = pos.row,
        character = vim.str_utfindex(line, client.offset_encoding, math.min(pos.col, #line), false),
      },
    }
  end, function(results)
    cancel = nil
    local ids = vim.tbl_keys(results)
    table.sort(ids)
    local sections = {}
    for _, id in ipairs(ids) do
      local response = results[id]
      if response.err then
        log.debug("hover error from client %d: %s", id, response.err.message)
      else
        local section = to_section(response.result)
        if section then
          sections[#sections + 1] = section
        end
      end
    end
    callback(sections)
  end)
end

return M
