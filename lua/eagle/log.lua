local config = require("eagle.config")

local M = {}

---Debug logging, visible in :messages. No-op unless config.options.logging is set.
---@param fmt string
---@param ... any string.format arguments
function M.debug(fmt, ...)
  if not config.options.logging then
    return
  end
  vim.notify("[eagle] " .. string.format(fmt, ...), vim.log.levels.DEBUG)
end

---Warnings about real problems; shown regardless of the logging option.
---@param fmt string
---@param ... any string.format arguments
function M.warn(fmt, ...)
  vim.notify("[eagle] " .. string.format(fmt, ...), vim.log.levels.WARN)
end

return M
