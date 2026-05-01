local config = require("eagle.config")

local M = {}

-- keep track of eagle window id and eagle buffer id
local eagle_buf = nil

-- tables that hold the diagnostics and lsp info
--M.diagnostic_messages = {}
--M.lsp_info = {}

--load and sort all the diagnostics of the current buffer
--M.sorted_diagnostics = {}

--keyboard_event is the same as with M.create_eagle_win(keyboard_event)
local function getpos(keyboard_event)
  if keyboard_event then
    local cursor_pos = vim.fn.getcurpos()
    return { row = cursor_pos[2] - 1, col = cursor_pos[3] - 1 }
  else
    local mouse_pos = vim.fn.getmousepos()
    return { row = mouse_pos.line - 1, col = mouse_pos.column - 1 }
  end
end

function M.sort_buf_diagnostics()
  M.sorted_diagnostics = vim.diagnostic.get(0, { bufnr = "%" })

  table.sort(M.sorted_diagnostics, function(a, b)
    return a.lnum < b.lnum
  end)
end

local function sanitize_markdown_line(line)
  if not line then
    return line
  end

  local sanitized = line
  sanitized = sanitized:gsub("\\([()%[%]{}%.%+%-%_%*`#!<>])", "%1")
  return sanitized
end

function M.debug_lsp_clients(opts)
  opts = opts or {}
  local output_to_buffer = opts.buffer or false
  local detailed = opts.detailed or false

  local clients = vim.lsp.get_clients()
  local output = {}

  -- Helper function to handle both buffer and print output
  local function add(str)
    if output_to_buffer then
      table.insert(output, str)
    else
      print(str)
    end
  end

  if #clients == 0 then
    add("No LSP clients found")
    if output_to_buffer then
      return output
    else
      return
    end
  end

  add("\n---- LSP Client Debug Information ----")
  add("Total clients: " .. #clients)

  for i, client in ipairs(clients) do
    add("\n" .. string.rep("=", 50))
    add("Client " .. i .. ": " .. (client.name or "unnamed"))
    add(string.rep("=", 50))

    -- Basic information
    add("\n## Basic Information")
    add("• Name: " .. (client.name or "unnamed"))
    add("• ID: " .. client.id)
    add("• Status: " .. (client:is_stopped() and "Stopped" or "Running"))

    -- Root directory
    if client.config and client.config.root_dir then
      add("• Root directory: " .. tostring(client.config.root_dir))
    end

    -- Filetypes (resolved from vim.lsp.config registry; ClientConfig no longer carries them)
    local registered_cfg = vim.lsp.config[client.name]
    local filetypes = registered_cfg and registered_cfg.filetypes
    if filetypes then
      add("• Supported filetypes: " .. vim.inspect(filetypes))
    else
      add("• Supported filetypes: none specified")
    end

    -- Attached buffers
    local attached_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.lsp.buf_is_attached(buf, client.id) then
        local name = vim.api.nvim_buf_get_name(buf)
        name = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
        local ft = vim.bo[buf].filetype
        table.insert(attached_buffers, { id = buf, name = name, ft = ft })
      end
    end

    add("\n## Attached Buffers (" .. #attached_buffers .. ")")
    if #attached_buffers > 0 then
      for _, buf in ipairs(attached_buffers) do
        add(string.format("• Buffer %d: %s (%s)", buf.id, buf.name, buf.ft))
      end
    else
      add("• None")
    end

    -- List supported methods
    add("\n## Supported Methods")
    local common_methods = {
      "textDocument/hover",
      "textDocument/signatureHelp",
      "textDocument/definition",
      "textDocument/implementation",
      "textDocument/references",
      "textDocument/documentSymbol",
      "textDocument/codeAction",
      "textDocument/codeLens",
      "textDocument/formatting",
      "textDocument/rangeFormatting",
      "textDocument/rename",
      "textDocument/completion",
      "textDocument/declaration",
      "textDocument/typeDefinition",
      "textDocument/publishDiagnostics",
      "textDocument/semanticTokens/full",
      "workspace/symbol",
    }

    for _, method in ipairs(common_methods) do
      add("• " .. method .. ": " .. tostring(client:supports_method(method)))
    end

    -- Server capabilities (detailed info)
    if client.server_capabilities then
      add("\n## Capabilities Details")

      -- Completion
      if client.server_capabilities.completionProvider then
        add("• Completion Provider:")
        if client.server_capabilities.completionProvider.triggerCharacters then
          add(
            "  - Trigger Characters: " .. vim.inspect(client.server_capabilities.completionProvider.triggerCharacters)
          )
        end
        if client.server_capabilities.completionProvider.resolveProvider then
          add("  - Resolve Provider: true")
        end
      end

      -- Hover
      if type(client.server_capabilities.hoverProvider) == "table" then
        add("• Hover Provider Details: " .. vim.inspect(client.server_capabilities.hoverProvider))
      end

      -- Signature Help
      if client.server_capabilities.signatureHelpProvider then
        add("• Signature Help Provider:")
        if client.server_capabilities.signatureHelpProvider.triggerCharacters then
          add(
            "  - Trigger Characters: "
              .. vim.inspect(client.server_capabilities.signatureHelpProvider.triggerCharacters)
          )
        end
      end

      -- Code Actions
      if type(client.server_capabilities.codeActionProvider) == "table" then
        add("• Code Action Provider:")
        if client.server_capabilities.codeActionProvider.codeActionKinds then
          add("  - Action Kinds: " .. vim.inspect(client.server_capabilities.codeActionProvider.codeActionKinds))
        end
      end

      -- Semantic Tokens
      if client.server_capabilities.semanticTokensProvider then
        add("• Semantic Tokens Provider:")
        if client.server_capabilities.semanticTokensProvider.legend then
          add("  - Token Types: " .. #client.server_capabilities.semanticTokensProvider.legend.tokenTypes)
          add("  - Token Modifiers: " .. #client.server_capabilities.semanticTokensProvider.legend.tokenModifiers)
        end
        if detailed then
          add(
            "  - Token Types List: " .. vim.inspect(client.server_capabilities.semanticTokensProvider.legend.tokenTypes)
          )
          add(
            "  - Token Modifiers List: "
              .. vim.inspect(client.server_capabilities.semanticTokensProvider.legend.tokenModifiers)
          )
        end
      end

      -- Workspace
      if client.server_capabilities.workspace then
        add("\n• Workspace Capabilities:")

        -- Workspace folders
        if client.server_capabilities.workspace.workspaceFolders then
          add("  - Workspace Folders: Supported")
        end

        -- File operations
        if client.server_capabilities.workspace.fileOperations then
          add("  - File Operations: Supported")
        end
      end

      -- Document Sync details
      if client.server_capabilities.textDocumentSync then
        local sync_kind = type(client.server_capabilities.textDocumentSync) == "table"
            and client.server_capabilities.textDocumentSync.change
          or client.server_capabilities.textDocumentSync

        local sync_kind_text = {
          [0] = "None",
          [1] = "Full",
          [2] = "Incremental",
        }

        add("• Text Document Sync: " .. (sync_kind_text[sync_kind] or "Unknown"))

        if type(client.server_capabilities.textDocumentSync) == "table" then
          local sync = client.server_capabilities.textDocumentSync --[[@as table]]
          if sync.willSave then
            add("  - Will Save: true")
          end
          if sync.willSaveWaitUntil then
            add("  - Will Save Wait Until: true")
          end
          if sync.save then
            add("  - Did Save: true")
          end
        end
      end
    end

    -- Custom handlers
    local handlers = {}
    if client.handlers and detailed then
      add("\n## Custom Handlers")
      for handler_name, _ in pairs(client.handlers) do
        table.insert(handlers, handler_name)
      end
      table.sort(handlers)
      for _, handler_name in ipairs(handlers) do
        add("• " .. handler_name)
      end
    end

    -- Server settings
    if client.config and client.config.settings and detailed then
      add("\n## Server Settings")
      add(vim.inspect(client.config.settings))
    end

    -- Initialization options
    if client.config and client.config.init_options and detailed then
      add("\n## Initialization Options")
      add(vim.inspect(client.config.init_options))
    end
  end

  add("\n" .. string.rep("=", 50))

  -- Output to buffer if requested
  if output_to_buffer then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    -- Open buffer in split window
    vim.cmd("split LSP-Debug")
    vim.api.nvim_win_set_buf(0, buf)
    return buf
  end
end

local function check_lsp_support()
  -- get the filetype of the current buffer
  local filetype = vim.bo.filetype

  -- get all active clients
  local clients = vim.lsp.get_clients()

  -- filter the clients based on the filetype of the current buffer
  -- (filetypes were removed from vim.lsp.ClientConfig; resolve via the registered vim.lsp.config)
  local relevant_clients = {}
  for _, client in ipairs(clients) do
    local registered_cfg = vim.lsp.config[client.name]
    local filetypes = registered_cfg and registered_cfg.filetypes
    if filetypes and vim.tbl_contains(filetypes, filetype) then
      table.insert(relevant_clients, client)
    end
  end

  -- check if any of the relevant clients support textDocument/hover
  for _, client in ipairs(relevant_clients) do
    if client:supports_method("textDocument/hover") then
      if config.options.logging then
        print("Found LSP client supporting textDocument/hover: " .. client.name)
      end
      return true
    end
  end

  return false
end

--keyboard_event is the same as with M.create_eagle_win(keyboard_event)
function M.load_lsp_info(keyboard_event, callback)
  --Ideally we need this binded with Event(s)
  --As of right now, WinEnter is a partial solution,
  --but it's not enough (for buffers etc).
  --BufEnter doesn't seem to work properly
  local has_lsp = check_lsp_support()

  if not has_lsp then
    if config.options.logging then
      print("No LSP support detected, skipping LSP info loading")
    end
    M.lsp_info = {}
    callback()
    return
  end

  M.lsp_info = {}

  local pos = getpos(keyboard_event)
  local clients = vim.lsp.get_clients()
  local win = vim.api.nvim_get_current_win()
  local position_params = vim.lsp.util.make_position_params(win, clients[1].offset_encoding or "utf-16")

  position_params.position.line = pos.row
  position_params.position.character = pos.col

  local bufnr = vim.api.nvim_get_current_buf()

  -- asynchronous, so we need to use a callback function
  -- buf_request_sync contains vim.wait which is unwanted
  vim.lsp.buf_request_all(bufnr, "textDocument/hover", position_params, function(results)
    for _, result in pairs(results) do
      if result.result and result.result.contents then
        M.lsp_info = vim.lsp.util.convert_input_to_markdown_lines(result.result.contents)
      end
    end

    -- Call the callback function after lsp_info has been populated
    callback()
  end)
end

--keyboard_event is the same as with M.create_eagle_win(keyboard_event)
function M.load_diagnostics(keyboard_event)
  local pos = getpos(keyboard_event)
  local diagnostics
  local prev_diagnostics = M.diagnostic_messages
  M.diagnostic_messages = {}

  local pos_info = vim.inspect_pos(vim.api.nvim_get_current_buf(), pos.row, pos.col)
  for _, extmark in ipairs(pos_info.extmarks) do
    local extmark_str = vim.inspect(extmark)
    if string.find(extmark_str, "Diagnostic") then
      diagnostics = vim.diagnostic.get(0, { lnum = pos.row })

      --binary search on the sorted sorted_diagnostics table
      --needed for nested underlines (poor API)
      if #diagnostics == 0 then
        local outer_line
        if M.sorted_diagnostics then
          local low, high = 1, #M.sorted_diagnostics
          while low <= high do
            local mid = math.floor((low + high) / 2)
            local diagnostic = M.sorted_diagnostics[mid]
            if diagnostic.lnum < pos.row then
              outer_line = diagnostic.lnum
              low = mid + 1
            else
              high = mid - 1
            end
          end
        end
        diagnostics = vim.diagnostic.get(0, { lnum = outer_line })
      end
    end
  end

  if diagnostics and #diagnostics > 0 then
    for _, diagnostic in ipairs(diagnostics) do
      local cursor_in_v_bounds, cursor_in_h_bounds
      local end_lnum = diagnostic.end_lnum or diagnostic.lnum
      local end_col = diagnostic.end_col
      if not end_col or (diagnostic.lnum == end_lnum and end_col <= diagnostic.col) then
        -- fallback for zero-width diagnostics that still place an underline
        end_col = diagnostic.col + 1
      end

      -- check if the mouse is within the vertical bounds of the diagnostic (single-line or otherwise)
      cursor_in_v_bounds = (diagnostic.lnum <= pos.row) and (pos.row <= end_lnum)

      if cursor_in_v_bounds then
        if diagnostic.lnum == end_lnum then
          -- if its a single-line diagnostic

          -- check if the mouse is within the horizontal bounds of the diagnostic
          cursor_in_h_bounds = (diagnostic.col <= pos.col) and (pos.col < end_col)
        else
          -- if its a multi-line diagnostic (nested)

          -- suppose we are always within the horizontal bounds of the diagnostic
          -- other checks (EOL, whitespace etc) were handled in process_mouse_pos (already optimized)
          cursor_in_h_bounds = true
        end
      end

      if cursor_in_v_bounds and cursor_in_h_bounds then
        table.insert(M.diagnostic_messages, diagnostic)
      end
    end
  end

  if not vim.deep_equal(M.diagnostic_messages, prev_diagnostics) then
    return false
  end

  return true
end

--keyboard_event is true when the eagle window was invoked using the keyboard and not the mouse
--useful for hybrid scenario (keyboard + mouse enabled at the same time)
function M.create_eagle_win(keyboard_event)
  local messages = {}
  local has_diagnostics = #M.diagnostic_messages > 0

  -- Check if M.lsp_info has any non-empty, meaningful content
  local has_lsp_info = false
  local lsp_has_codefence = false
  if config.options.show_lsp_info and #M.lsp_info > 0 then
    for _, md_line in ipairs(M.lsp_info) do
      if md_line ~= "" and md_line ~= "---" then
        has_lsp_info = true
        break
      end
    end
    for _, md_line in ipairs(M.lsp_info) do
      if md_line:match("^```") then
        lsp_has_codefence = true
        break
      end
    end
  end

  local function add_diagnostics()
    if not has_diagnostics then
      return
    end

    local filtered_diagnostic_messages = {}
    if config.options.diagnostic_filter then
      for _, d in ipairs(M.diagnostic_messages) do
        if config.options.diagnostic_filter(d) then
          table.insert(filtered_diagnostic_messages, d)
        end
      end
    else
      filtered_diagnostic_messages = M.diagnostic_messages
    end

    if #filtered_diagnostic_messages == 0 then
      return
    end

    if config.options.show_headers then
      table.insert(messages, "# Diagnostics")
      table.insert(messages, "")
    end

    local severity_title = {
      [vim.diagnostic.severity.ERROR] = "ERROR",
      [vim.diagnostic.severity.WARN] = "WARNING",
      [vim.diagnostic.severity.INFO] = "INFO",
      [vim.diagnostic.severity.HINT] = "HINT",
    }

    for i, d in ipairs(filtered_diagnostic_messages) do
      local meta = nil
      if d.source and d.code then
        -- e.g. "Lua Diagnostic (undefined-global)"
        meta = string.format("%s(%s)", d.source, d.code)
      elseif d.source then
        meta = string.format("%s", d.source)
      elseif d.code then
        -- rare case: a server fills only the code field
        meta = string.format("%s", d.code)
      end

      local title = severity_title[d.severity]
      if meta then
        title = title .. " — " .. meta
      end

      table.insert(messages, ">[!" .. title .. "]")

      local formatter = config.options.source_formatters[d.source]
      local message = formatter and formatter(d) or d.message

      local message_parts = vim.split(message, "\n", { trimempty = false })
      for _, part in ipairs(message_parts) do
        table.insert(messages, sanitize_markdown_line(part))
      end

      local href = d.user_data
        and d.user_data.lsp
        and d.user_data.lsp.codeDescription
        and d.user_data.lsp.codeDescription.href

      if href then
        table.insert(messages, "[View documents](" .. href .. ")")
      end

      if i < #filtered_diagnostic_messages then
        table.insert(messages, "___")
      end
    end
  end

  local function add_lsp_info()
    if has_lsp_info then
      if config.options.show_headers then
        table.insert(messages, "# LSP Info")
        table.insert(messages, "")
      end
      local in_code_block = false
      for _, md_line in ipairs(M.lsp_info) do
        if md_line:match("^```") then
          in_code_block = not in_code_block
          table.insert(messages, md_line)
        elseif md_line == "---" then
          table.insert(messages, "___")
        elseif md_line ~= "" then
          local line = in_code_block and md_line or sanitize_markdown_line(md_line)
          table.insert(messages, line)
        end
      end
    end
  end

  -- Set row position based on mouse/cursor
  local row
  local relative
  local focusable
  if keyboard_event then
    row = vim.fn.winline()
    relative = "cursor"
    focusable = false
  else
    row = vim.fn.getmousepos().screenrow
    relative = "mouse"
    focusable = true
  end

  -- Determine if the window should be rendered above or below the mouse/cursor
  local render_above
  if row > math.floor(vim.o.lines / 2) then
    render_above = true
  else
    render_above = false
  end

  -- Adjust the order and insert '___' appropriately
  if config.options.order == 1 then
    add_diagnostics()
    if has_diagnostics and has_lsp_info then
      table.insert(messages, "___")
    end
    add_lsp_info()
  elseif config.options.order == 2 then
    if render_above then
      add_diagnostics()
      if has_diagnostics and has_lsp_info then
        table.insert(messages, "___")
      end
      add_lsp_info()
    else
      add_lsp_info()
      if has_diagnostics and has_lsp_info then
        table.insert(messages, "___")
      end
      add_diagnostics()
    end
  elseif config.options.order == 3 then
    add_lsp_info()
    if has_diagnostics and has_lsp_info then
      table.insert(messages, "___")
    end
    add_diagnostics()
  elseif config.options.order == 4 then
    if render_above then
      add_lsp_info()
      if has_diagnostics and has_lsp_info then
        table.insert(messages, "___")
      end
      add_diagnostics()
    else
      add_diagnostics()
      if has_diagnostics and has_lsp_info then
        table.insert(messages, "___")
      end
      add_lsp_info()
    end
  end

  -- Apply severity callout transformation up-front so width/height are computed
  -- against what's actually rendered (icon + meta), not the ">[!ERROR ...]" source.
  local highlight_lines = {}
  local render_config = type(config.options.improved_markdown) == "boolean" and {} or config.options.improved_markdown
  if config.options.improved_markdown then
    for idx, msg in ipairs(messages) do
      local severity, meta = msg:match("^%s*>%[%!(%u+)%s*—%s*(.+)%]")
      local severity_renderer = render_config.severity_renderer
      if severity and meta and severity_renderer and severity_renderer[severity] then
        local render = severity_renderer[severity]
        messages[idx] = render.icon .. meta
        table.insert(highlight_lines, { line = idx - 1, hl = render.hl })
      end
    end
  end

  -- Determine max content width. Separator placeholders ("___") are excluded since
  -- they will be expanded to fill the window width once that's known.
  local replace_separators = config.options.improved_markdown and render_config.replace_dashes
  local max_line_width = 0
  for _, msg in ipairs(messages) do
    if not (msg == "___" and replace_separators) then
      max_line_width = math.max(max_line_width, vim.fn.strdisplaywidth(msg))
    end
  end

  -- need + 1 for hyperlinks (shift + click); + 1 more for the leading-space pad
  local max_content_width = config.options.get_max_width()
  local max_allowed_width = max_content_width + config.options.scrollbar_offset + 2
  local width = math.max(
    math.min(max_line_width + config.options.scrollbar_offset + 2, max_allowed_width),
    vim.fn.strdisplaywidth(config.options.title)
  )

  -- Separator spans the visible content area: window width minus leading space
  -- and the scrollbar margin reserved on the right.
  local separator_width = math.max(1, width - 1 - config.options.scrollbar_offset)

  -- Build final buffer lines: replace separator placeholders, prepend leading-space pad.
  local final_lines = {}
  for _, msg in ipairs(messages) do
    if msg == "___" and replace_separators then
      table.insert(final_lines, " " .. string.rep("─", separator_width))
    else
      table.insert(final_lines, " " .. msg)
    end
  end

  -- create a buffer with buflisted = false and scratch = true
  if eagle_buf then
    vim.api.nvim_buf_delete(eagle_buf, {})
  end
  eagle_buf = vim.api.nvim_create_buf(false, true)

  vim.bo[eagle_buf].filetype = "markdown"
  vim.treesitter.start(eagle_buf)
  vim.api.nvim_buf_set_lines(eagle_buf, 0, -1, false, final_lines)

  -- Apply severity callout highlights (deferred so treesitter doesn't override them)
  if #highlight_lines > 0 then
    vim.schedule(function()
      local ns = vim.api.nvim_create_namespace("markdown_callout_titles")
      for _, h in ipairs(highlight_lines) do
        vim.hl.range(eagle_buf, ns, h.hl, { h.line, 0 }, { h.line, -1 })
      end
    end)
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = eagle_buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = eagle_buf })

  -- Compute window height from the wrapped display row count of each line.
  -- With breakindent enabled, continuations indent by 1 col to match the leading
  -- space, so each wrapped row past the first holds (width - 1) cols of content.
  local first_capacity = width
  local cont_capacity = math.max(1, width - 1)
  local total_rows = 0
  for _, line in ipairs(final_lines) do
    local lw = vim.fn.strdisplaywidth(line)
    if lw <= first_capacity then
      total_rows = total_rows + 1
    else
      total_rows = total_rows + 1 + math.ceil((lw - first_capacity) / cont_capacity)
    end
  end

  -- Subtract 1 for the lsp info code fence (```)
  if has_lsp_info and lsp_has_codefence then
    total_rows = total_rows - 1
  end

  local height = math.max(math.min(total_rows, config.options.get_max_height()), 1)

  vim.api.nvim_set_hl(0, "TitleColor", { fg = config.options.title_color })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = config.options.border_color })

  --this determines if the window should be rendered above or below the mouse/cursor
  if render_above then
    row = config.options.window_row - height - 3
  else
    row = config.options.window_row
  end

  M.eagle_win = vim.api.nvim_open_win(eagle_buf, false, {
    title = { { config.options.title, "TitleColor" } },
    title_pos = config.options.title_pos,
    relative = relative,
    row = row,
    col = -config.options.window_col,
    width = width,
    height = height,
    style = "minimal",
    border = config.options.border,
    focusable = focusable,
  })

  vim.api.nvim_set_option_value("wrap", true, { win = M.eagle_win })
  vim.api.nvim_set_option_value("linebreak", true, { win = M.eagle_win })
  vim.api.nvim_set_option_value("breakindent", true, { win = M.eagle_win })

  if config.options.improved_markdown then
    vim.api.nvim_set_option_value("conceallevel", config.options.conceallevel, { win = M.eagle_win })
    vim.api.nvim_set_option_value("concealcursor", config.options.concealcursor, { win = M.eagle_win })
  end

  if config.options.on_open then
    config.options.on_open(M.eagle_win, eagle_buf)
  end
end

return M
