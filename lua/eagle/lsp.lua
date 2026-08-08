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
local function is_rule(line)
  return line:match("^%s*%-%-%-+%s*$") ~= nil or line:match("^%s*___+%s*$") ~= nil
end

---Convert one client's hover result into markdown lines, compacted: blank
---lines are dropped (except inside code fences, where they are real code) and
---separator rules at the section edges are stripped, so a payload that ends
---with "---" does not render a dangling rule. Returns nil when nothing but
---blanks and rules remain.
---@param result lsp.Hover?
---@return string[]?
local function to_section(result)
  if not result or not result.contents then
    return nil
  end
  local section = {}
  local in_fence = false
  local has_content = false
  for _, line in ipairs(vim.lsp.util.convert_input_to_markdown_lines(result.contents)) do
    if line:match("^%s*```") then
      in_fence = not in_fence
      section[#section + 1] = line
      has_content = true
    elseif in_fence then
      section[#section + 1] = line
    elseif not line:match("^%s*$") then
      section[#section + 1] = line
      has_content = has_content or not is_rule(line)
    end
  end
  while section[1] and is_rule(section[1]) do
    table.remove(section, 1)
  end
  while section[#section] and is_rule(section[#section]) do
    table.remove(section)
  end
  if #section == 0 or not has_content then
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
