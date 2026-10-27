local M = {}

---@class TidalBootConfig
---@field tidal TidalProcConfig
---@field sclang TidalSclangConfig
---@field split "v" | nil

--- Connect to an existing process instead of spawning one.
--- Type created to allow for a potential TCP backend
---@alias TidalRemote { unix: string, eventIdBase?: integer }

--- SuperDirt boot configuration (see tidal/core/sclang.lua)
---@class TidalSclangConfig
---@field cmd string
---@field file string? path to the BootSuperDirt.scd file; required when enabled
---@field args table<string>
---@field enabled boolean
---@field wait integer seconds to wait for the ready file before giving up
---@field ready_file string? file written by the boot file once SuperDirt is up; nil = no readiness check

---@class TidalProcConfig
---@field cmd string
---@field file string
---@field args table<string>
---@field enabled boolean
---@field remote? TidalRemote

---@class TidalConfig
local defaults = {
  boot = {
    --- Boot SuperDirt before Tidal (see Boot in the README)
    sclang = {
      --- Command to launch SuperCollider with; boot file is appended
      cmd = "sclang",
      args = {},
      --- SuperDirt boot file path. Required when enabled is true.
      file = nil,
      enabled = false,
      --- Seconds to wait for the ready file before giving up
      wait = 60,
      --- File written by the boot file once SuperDirt is ready; polled after
      --- spawning sclang and before ghci starts. nil = no readiness check.
      ready_file = nil,
    },
    --- Configure TidalLaunch command
    tidal = {
      --- Command to launch ghci with tidal installation
      cmd = "ghci",
      args = {
        "-v0",
      },
      --- Tidal boot file path
      file = vim.api.nvim_get_runtime_file("bootfiles/BootTidal.hs", false)[1],
      enabled = true,
      remote = nil,
      highlight = {
        type = "stdio",
        styles = {
          osc = {
            ip = "127.0.0.1",
            port = 3335,
          },
          custom = {},
          global = { baseName = "CodeHighlight", style = { bg = "#7eaefc", foreground = "#000000" } },
        },
        events = {
          osc = {
            ip = "127.0.0.1",
            port = 6013,
          },
        },
        fps = 60,
        --- Publish on-screen rectangles of `dN` pattern blocks as `/tidal/blocks` OSC
        --- messages (see tidal/highlighting/positions.lua). Disabled when nil.
        --- @type { ip: string, port: integer } | nil
        positions = nil,
        --- Relay raw terminal output received over UDP to the host terminal via
        --- nvim_ui_send() (see tidal/highlighting/relay.lua). Disabled when nil.
        --- @type { ip: string, port: integer } | nil
        relay = nil,
        onSamChange = function() end,
        onPlayStateChange = function() end,
        onParsedOutputChange = function() end,
      },
    },
    split = "v",
  },
  --- Default keymaps
  --- Set to false to disable all default mappings
  --- @type table | nil
  mappings = {
    send_line = { mode = { "i", "n" }, key = "<S-CR>" },
    send_visual = { mode = { "x" }, key = "<S-CR>" },
    send_block = { mode = { "i", "n", "x" }, key = "<M-CR>" },
    send_node = { mode = "n", key = "<leader><CR>" },
    send_silence = { mode = "n", key = "<leader>d" },
    send_hush = { mode = "n", key = "<leader>h" },
  },
  ---- Configure highlight applied to selections sent to tidal interpreter
  selection_highlight = {
    --- Highlight definition table
    --- see ':h nvim_set_hl' for details
    --- @type vim.api.keyset.highlight
    highlight = { link = "IncSearch" },
    --- Duration to apply the highlight for
    timeout = 150,
  },
}

---@type TidalConfig
M.options = defaults

M.namespace = vim.api.nvim_create_namespace("Tidal")

---Configure Tidal plugin
---@param options TidalConfig | nil
function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

M.setup()

return M
