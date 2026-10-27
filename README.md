# tidal-events.nvim

A Neovim plugin for livecoding with [TidalCycles](https://tidalcycles.org), with
event highlighting and hooks for driving external visualizers from your code.

This is a fork of [thgrund/tidal.nvim](https://github.com/thgrund/tidal.nvim)
(whose development has since moved to
[codeberg.org/MrReason/tidal.nvim](https://codeberg.org/MrReason/tidal.nvim)).
It keeps the upstream feature set and adds:

- **Pattern block positions**: publishes the on-screen rectangle of every
  `dN $ ...` block over OSC, so external tools can draw per-pattern content
  behind your code (see [Pattern block positions](#pattern-block-positions)).
- **Terminal relay**: lets a background process write terminal sequences to the
  host terminal through Neovim's own UI, safely serialized with its redraws
  (see [Terminal relay](#terminal-relay)).

- **Ghostty audio visualizer** (optional extras): live waveforms behind each
  `dN` block and audio-reactive terminal shaders for
  [Ghostty](https://ghostty.org), built on the two features above (see
  [extras/ghostty](extras/ghostty/README.md)).

All are opt-in and disabled by default.

![pluginExample](./assets/pluginExample.png)

## Features

- User commands to start/stop Tidal processes in Neovim's built-in terminal
  (see [Boot](#boot))
- Send code to Tidal using built-in [keymaps](#keymaps)
- Write your own keymaps and functions with the Lua [API](#api)
- Haskell syntax highlighting for `.tidal` files
- Event highlighting for mini-notation patterns
- Tidal stdout/stderr in a separate buffer that can be closed and reopened
- Optional OSC feeds for visualizers (block positions, terminal relay)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "l00sed/tidal-events.nvim",
  ft = { "tidal" },
  opts = {
    -- Your configuration here
    -- See the configuration section for defaults
  },
  -- Recommended: Treesitter parser for Haskell (needed for send_node)
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "haskell" } },
  },
}
```

## Configuration

Defaults:

```lua
{
  --- Configure TidalLaunch command
  boot = {
    tidal = {
      --- Command to launch ghci with tidal installation
      cmd = "ghci",
      args = { "-v0" },
      --- Tidal boot file path (defaults to the one shipped in bootfiles/)
      file = vim.api.nvim_get_runtime_file("bootfiles/BootTidal.hs", false)[1],
      enabled = true,
      --- Connect to an existing Tidal process instead (see Remote backends)
      remote = nil,
      highlight = {
        --- How highlight events are received: "stdio", "socket" or "osc"
        type = "stdio",
        styles = {
          osc = { ip = "127.0.0.1", port = 3335 },
          -- [Tidal ID] -> hl style
          custom = {},
          global = { baseName = "CodeHighlight", style = { bg = "#7eaefc", foreground = "#000000" } },
        },
        events = {
          osc = { ip = "127.0.0.1", port = 6013 },
        },
        fps = 60,
        --- Publish dN block rectangles as /tidal/blocks OSC messages
        --- @type { ip: string, port: integer } | nil
        positions = nil,
        --- Relay UDP datagrams to the host terminal via nvim_ui_send()
        --- @type { ip: string, port: integer } | nil
        relay = nil,
      },
    },
    split = "v",
  },
  --- Default keymaps. Set to false to disable all default mappings
  mappings = {
    send_line = { mode = { "i", "n" }, key = "<S-CR>" },
    send_visual = { mode = { "x" }, key = "<S-CR>" },
    send_block = { mode = { "i", "n", "x" }, key = "<M-CR>" },
    send_node = { mode = "n", key = "<leader><CR>" },
    send_silence = { mode = "n", key = "<leader>d" },
    send_hush = { mode = "n", key = "<leader>h" },
  },
  --- Highlight applied to selections sent to the tidal interpreter
  selection_highlight = {
    --- See :h nvim_set_hl
    highlight = { link = "IncSearch" },
    --- Duration to apply the highlight for (ms)
    timeout = 150,
  },
}
```

## Usage

### Boot

- `:TidalLaunch` (or `:Tidal`): starts the TidalCycles process
- `:TidalQuit`: stops the TidalCycles process
- `:TidalNotification`: opens a buffer showing the stdout and stderr of the
  Tidal REPL session

By default, `ghci` runs the `BootTidal.hs` provided by this plugin. SuperDirt
(SuperCollider) is not started by the plugin; boot it yourself, e.g. with
[scnvim](#example-integrating-with-scnvim) or an autocommand.

#### Remote backends

Instead of spawning `ghci`, tidal-events.nvim can connect to an existing Tidal
process over a Unix socket, e.g. to let several editors share one session:

```lua
boot = {
  tidal = {
    remote = {
      --- Path to the Unix domain socket exposed by the running ghci process
      unix = "/tmp/tidal.sock",
      --- Optional: starting event ID (prevents collisions between editors)
      eventIdBase = 0,
    },
  },
},
```

### Keymaps

Available in `.tidal` files:

- `send_line`: sends the current line
- `send_block`: sends the contiguous block of non-empty lines around the cursor
- `send_node`: sends the expression under the cursor (needs the Haskell
  treesitter parser)
- `send_visual`: sends the current visual selection
- `send_silence`: sends `d<count> silence` (`d1` without a count)
- `send_hush`: sends `hush`, silencing all patterns

### Autocommands

User autocommands for custom functionality:

- `TidalLaunch`: fired by `launch_tidal`
- `TidalHush`: fired whenever a hush command is sent

#### Example: integrating with scnvim

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "TidalLaunch",
  callback = function()
    require("scnvim").start()
    local file = assert(io.open("/path/to/BootSuperDirt.scd", "r"), "bootfile not found")
    require("scnvim").send(file:read("a"))
  end,
})
```

### Event highlighting

Highlights the mini-notation events as they play. Built for TidalCycles >= 1.10
and enabled automatically. With a custom `BootTidal.hs`, add the clock target:

```haskell
let clockShape = OSC "/ping" $ Named {requiredArgs = ["clock"]}
let clockTarget = Target {oName = "clock", oAddress = "127.0.0.1", oPort = 6013, oLatency = ((3/10)), oSchedule = Live, oWindow = Nothing, oHandshake = False, oBusPort = Nothing }

tidalInst <- mkTidalWith [(superdirtTarget { oLatency = -0.02 }, [superdirtShape]), (clockTarget, [clockShape])] (defaultConfig {cFrameTimespan = 1/50, cProcessAhead = 1/20})
```

Styles accept anything supported by
[nvim_set_hl](https://neovim.io/doc/user/api.html#nvim_set_hl()).

Global style (the `baseName` also applies to remote styles):

```lua
highlight = {
  styles = {
    global = { baseName = "CodeHighlight", style = { bg = "#7eaefc", foreground = "#000000" } },
  },
},
```

Per-stream styles (`"1"` = `d1`; named patterns like `p "drums"` work too):

```lua
highlight = {
  styles = {
    custom = {
      ["drums"] = { bg = "#e7b9ed", foreground = "#000000" },
      ["2"] = { bg = "#b9edc7", foreground = "#000000" },
    },
  },
},
```

Remote styles over OSC, e.g. from SuperCollider:

```supercollider
NetAddr("127.0.0.1", 3335).sendMsg("/neovim/eventhighlighting/addstyle", "1", "#e7b9ed");
```

### Pattern block positions

Publishes the on-screen position of each pattern block so external
visualizers can follow your code. A block starts at a line beginning with `dN`
(`d1 $ ...`, `d12 $ ...`) and runs until the next blank line or `dN` line.

```lua
highlight = {
  positions = { ip = "127.0.0.1", port = 57130 },
},
```

Message `/tidal/blocks`, sent every highlight frame and immediately on scroll,
resize, zoom, buffer switches and edits:

| Argument | Type | Meaning |
|---|---|---|
| target | string | `$TMUX_PANE` inside tmux, otherwise the host terminal device (e.g. `/dev/ttys003`), or `""` |
| lines, columns | int, int | Neovim's screen size |
| then per visible block: | | |
| id | int | pattern number (`d1` → 1) |
| top, bottom | int, int | screen rows (0-based, inclusive) |
| left, width | int, int | text area columns (0-based) |

Only the block each pattern was **last sent from** is reported. Other `dN`
definitions of the same pattern, in the same or other buffers, are ignored, so
sending a different `d2` moves the visual to it. The sent block is tracked
through edits; `dN silence` and `hush` remove patterns. Folds and scrolled-off
lines are excluded.

### Terminal relay

Lets an external process write raw terminal sequences (for example OSC 4
palette updates that feed a terminal shader) to the host terminal. Writing to
the terminal from outside would race Neovim's (or tmux's) own output and can
garble the screen. The relay instead sends them through `nvim_ui_send()`, so
they are serialized with Neovim's redraws. Requires Neovim >= 0.12.

```lua
highlight = {
  relay = { ip = "127.0.0.1", port = 57131 },
},
```

- Each UDP datagram's payload is written verbatim.
- Inside tmux it is wrapped in DCS passthrough, and `allow-passthrough` is
  enabled for Neovim's pane.
- On exit, the palette is reset (`OSC 104`).
- Only the first Neovim to bind the port relays; others skip silently.

### Ghostty audio visualizer

[extras/ghostty](extras/ghostty/README.md) contains a ready-made visualizer
built on block positions and the relay: an encoder script, Ghostty shaders and a
SuperDirt tap. Install it with:

```sh
sh extras/ghostty/install.sh   # from the plugin directory; --dry-run to preview
```

### API

Functions to roll your own keymaps or commands:

```lua
vim.api.nvim_create_user_command("InstantGabber", function()
  local tidal = require("tidal")
  tidal.api.send("setcps (200/60/4)")
  tidal.api.send_multiline({
    "d1 $ stack [",
    's "gabba*4" # speed 0.78,',
    's "<[~ sd:2]*4!3 [sd*4 [~ sd]!3]>",',
    's "~ hh:2*4"]',
  })
  tidal.api.send('d2 $ "amencutup*8" # irand 32 # crush 4 # speed (5/4)')
end, { desc = "Make gabber happen fast" })
```

See [api.lua](lua/tidal/api.lua) for the full list.

## Requirements

- macOS or Linux
- `ghc` with Tidal installed (see the
  [Tidal install docs](https://tidalcycles.org/docs/getting-started/linux_install))
- Neovim >= 0.10; the terminal relay needs >= 0.12 (`nvim_ui_send`)
- Haskell treesitter parser for `send_node`

## Contributing

Issues and pull requests are welcome at
[l00sed/tidal-events.nvim](https://github.com/l00sed/tidal-events.nvim).
Changes not specific to the visualizer features are better proposed upstream.

## Related projects

- [thgrund/tidal.nvim](https://github.com/thgrund/tidal.nvim) /
  [codeberg.org/MrReason/tidal.nvim](https://codeberg.org/MrReason/tidal.nvim):
  upstream of this fork
- [robbielyman/tidal.nvim](https://github.com/robbielyman/tidal.nvim): the
  original project
- [vim-tidal](https://github.com/tidalcycles/vim-tidal): Vim plugin for
  TidalCycles
- [vscode-tidalcycles](https://github.com/tidalcycles/vscode-tidalcycles):
  VS Code plugin for TidalCycles

## License

MIT, see [LICENSE](LICENSE).
