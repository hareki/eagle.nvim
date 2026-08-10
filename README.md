# 🦅 eagle.nvim

A Neovim plugin that shows diagnostics and LSP hover information in a floating window, following either the mouse or the keyboard cursor.

This is a heavily rewritten fork of [soulis-1256/eagle.nvim](https://github.com/soulis-1256/eagle.nvim). The config surface and internals are **not** compatible with upstream; see [Migrating from upstream](#migrating-from-upstream).

## Features

- **Mouse mode**: hover underlined code and, after a configurable idle delay, a float appears, like conventional GUI editors. Tracking is fully event-driven (no polling timers), and `vim.o.mousemoveevent` is managed for you.
- **Keyboard mode**: `:EagleWin` shows diagnostics + hover for the cursor position, `:EagleWinLineDiagnostic` shows every diagnostic on the current line.
- **Callout-style diagnostics**: each diagnostic renders as a severity icon + `source(code)` title line (highlighted per severity) above its message, with `[View documents](…)` links when the server provides them.
- **Real markdown rendering**: the float is a markdown buffer with treesitter highlighting, so fenced code blocks, links, and inline code render properly. Separators are emitted as thematic breaks (never setext underlines), optionally expanded to full-width rules.
- **Correct by construction**: per-client `offset_encoding` for hover requests, multi-client aggregation, diagnostics resolved against the window under the mouse (not the focused window), wrap-aware and conceal-aware window sizing via `nvim_win_text_height`.
- **Clean off-switch**: `mouse.enabled = false` registers zero mouse side effects; with both modes disabled, `setup()` registers nothing at all.

## Requirements

- Neovim **0.11+** (developed and tested on 0.12).
- An LSP server if you want hover info; set `show_lsp_info = false` otherwise.
- A [Nerd Font](https://www.nerdfonts.com/) for the default severity icons (override `render.severity` for plain text).

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hareki/eagle.nvim",
  opts = {},
}
```

Keyboard-only setup, lazy-loaded on its commands:

```lua
{
  "hareki/eagle.nvim",
  cmd = { "EagleWin", "EagleWinLineDiagnostic" },
  opts = {
    mouse = { enabled = false },
    keyboard = { enabled = true },
  },
}
```

## Configuration

Defaults:

```lua
require("eagle").setup({
  mouse = {
    -- Enable mouse tracking. Sets vim.o.mousemoveevent for you.
    -- When false, eagle registers no mouse side effects at all.
    enabled = true,
    -- ms the mouse must rest on a spot before the float opens
    render_delay = 500,
    -- ms without movement before the mouse counts as idle
    idle_delay = 50,
  },
  keyboard = {
    -- Register :EagleWin and :EagleWinLineDiagnostic
    enabled = false,
  },

  -- Section order of diagnostics (D) and LSP info (L). Left of the slash is
  -- the layout when the float opens above the anchor, right when below:
  -- 1. DL/DL   2. DL/LD   3. LD/LD   4. LD/DL
  order = 1,

  -- Show the "# Diagnostics" / "# LSP Info" section headers
  -- (also toggled by :EagleWinToggleHeaders)
  show_headers = true,

  -- Include LSP hover contents (same content as vim.lsp.buf.hover())
  show_lsp_info = true,

  -- Close the float when entering the command line
  close_on_cmd = true,

  -- Debug logging via vim.notify (check :messages)
  logging = false,

  -- Optional filter, applied when diagnostics are collected. Rejected
  -- diagnostics never influence whether the float opens.
  ---@type (fun(d: vim.Diagnostic): boolean?)?
  diagnostic_filter = nil,

  -- Message rewriters keyed by diagnostic.source. The returned string
  -- replaces the message and may contain markdown.
  ---@type table<string, fun(d: vim.Diagnostic): string>
  source_formatters = {},

  -- Runs after the float window is created (not on in-place updates)
  ---@type (fun(win: integer, buf: integer))?
  on_open = nil,

  render = {
    -- Callout title style per severity. Keys are vim.diagnostic.severity
    -- names; each entry needs an icon (string prefix) and a highlight group.
    severity = {
      ERROR = { icon = "󰅚 ", hl = "DiagnosticError" },
      WARN = { icon = "󰀪 ", hl = "DiagnosticWarn" },
      INFO = { icon = "󰋽 ", hl = "DiagnosticInfo" },
      HINT = { icon = "󰌶 ", hl = "DiagnosticHint" },
    },
    -- Expand separators into full-width "─" rules. When false, separators
    -- stay literal "___" thematic breaks (useful when another plugin, e.g.
    -- render-markdown.nvim, draws them for you).
    expand_separators = true,
    -- Strip backslash over-escaping that some LSP servers apply to markdown
    -- prose. Code fences and inline code spans are left untouched.
    unescape = true,
    -- Applied to the eagle window only
    conceallevel = 3,
    concealcursor = "nc",
    -- Rows your markdown renderer conceals per fenced code block. eagle sizes
    -- the float before such a renderer decorates the buffer, so it cannot see
    -- those rows vanish and would leave a blank row behind. Set 1 for
    -- render-markdown.nvim's default code.border = "hide" (closing fence
    -- concealed, opening fence kept as the language line), or 2 if the opening
    -- fence is concealed too.
    concealed_fence_rows = 0,
  },

  window = {
    -- "none", "single", "double", "rounded", "solid", "shadow", or a
    -- border table, see :h nvim_open_win
    border = "single",
    title = "",
    title_pos = "center", -- "left" | "center" | "right"
    -- Rows between the anchor (mouse/cursor) and the float
    row_offset = 1,
    -- Columns the float is shifted left of the anchor
    col_offset = 5,
    -- Extra right-side columns for scrollbar plugins
    scrollbar_offset = 0,
    -- Size caps, re-evaluated on every render (react to :vsplit / resize)
    max_width = function()
      return math.floor(vim.o.columns / 2)
    end,
    max_height = function()
      return math.floor(vim.o.lines / 2.5)
    end,
  },
})
```

## Usage

### Commands

| Command | Requires | Behavior |
|---|---|---|
| `:EagleWin` | `keyboard.enabled` | Diagnostics + hover for the cursor position. Repeat to focus the float, repeat again to close it. |
| `:EagleWinLineDiagnostic` | `keyboard.enabled` | Every diagnostic on the cursor line (any column), hover suppressed. Same focus/close cycle. |
| `:EagleWinToggleHeaders` | any mode | Toggle the section headers. |

### Lua API

```lua
local eagle = require("eagle")
eagle.setup(opts)                 -- idempotent; re-running replaces all state
eagle.is_open()                   -- boolean
eagle.close()
eagle.toggle_headers()
eagle.ignore_next_cursor_move()   -- suppress the next CursorMoved auto-close
```

`ignore_next_cursor_move()` exists because `noautocmd` cannot suppress `CursorMoved` ([vim/vim#2084](https://github.com/vim/vim/issues/2084)). Call it right before programmatically moving the cursor or switching windows, e.g. in `on_open` keymaps that jump between the float and the parent window:

```lua
on_open = function(eagle_win, eagle_buf)
  local parent_win = vim.api.nvim_get_current_win()
  vim.keymap.set("n", "<Tab>", function()
    require("eagle").ignore_next_cursor_move()
    vim.api.nvim_set_current_win(parent_win)
  end, { buffer = eagle_buf })
end
```

### Highlights

| Group | Default link | Applies to |
|---|---|---|
| `EagleNormal` | `NormalFloat` | Float background/text |
| `EagleBorder` | `FloatBorder` | Float border |
| `EagleTitle` | `FloatTitle` | Float title |

Callout title lines use the per-severity groups from `render.severity` (defaults: `DiagnosticError`, `DiagnosticWarn`, `DiagnosticInfo`, `DiagnosticHint`).

## Migrating from upstream

| Upstream | Here |
|---|---|
| `mouse_mode` / `keyboard_mode` | `mouse.enabled` / `keyboard.enabled` |
| `render_delay` / `detect_idle_timer` | `mouse.render_delay` / `mouse.idle_delay` |
| `max_width_factor` / `max_height_factor` | `window.max_width()` / `window.max_height()` functions |
| `window_row` / `window_col` | `window.row_offset` / `window.col_offset` |
| `border`, `title`, `title_pos`, `scrollbar_offset` | moved under `window.*` |
| `improved_markdown` | removed; the markdown pipeline is always on (`render.*` options) |
| `title_color`, `border_color`, `*_header_color`, `*_content_color` | `EagleNormal` / `EagleBorder` / `EagleTitle` highlight groups and `render.severity[*].hl` |
| `vim.o.mousemoveevent` set manually | set automatically when `mouse.enabled` |
| `require("eagle").ignore_cursor_moved = true` | `require("eagle").ignore_next_cursor_move()` |

## Troubleshooting

- **Nothing happens on hover**: check `:lua =vim.o.mousemoveevent` (should be `true` after `setup()` with mouse enabled) and confirm your terminal sends mouse-move events.
- **Icons render as tofu**: set plain-text icons, e.g. `render.severity.ERROR = { icon = "E ", hl = "DiagnosticError" }`.
- **Odd rendering in the float**: another markdown plugin may be attaching to the float's `markdown` buffer; configure it to ignore eagle's buffer or adjust `render.conceallevel`.
- **A blank row below a code block**: that plugin is concealing fence lines after eagle has already sized the float. Tell eagle how many rows it hides per code block with `render.concealed_fence_rows` (`1` for render-markdown.nvim's defaults).
- Set `logging = true` and check `:messages`.

## Acknowledgments

All credit for the original idea and design goes to [soulis-1256](https://github.com/soulis-1256), the author of upstream [eagle.nvim](https://github.com/soulis-1256/eagle.nvim). Consider [supporting them](https://www.paypal.com/paypalme/soulis1256).

## License

[Apache-2.0](./LICENSE)
