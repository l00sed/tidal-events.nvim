local boot = require("tidal.core.boot")
local highlight = require("tidal.highlighting")
local marker = require("tidal.highlighting.marker")
local message = require("tidal.core.message")
local notify = require("tidal.util.notify")
local sclang = require("tidal.core.sclang")
local select = require("tidal.util.select")
local state = require("tidal.core.state")
local util = require("tidal.util")
-- Lazily require highlight module to ensure 'setup' is called before

local M = {}

--- Spawn ghci, start event highlighting and mark the session live.
---@param args TidalBootConfig
local function start_tidal(args)
  local current_win = vim.api.nvim_get_current_win()
  if args.tidal.enabled then
    boot.tidal(args.tidal, args.split)
  end
  M.start_event_highlighting(args.tidal)
  vim.api.nvim_set_current_win(current_win)
  state.launched = true
end

--- Begin a Tidal session. When boot.sclang.enabled, SuperDirt (sclang) is booted
--- or reused first and ghci starts once it is ready. The TidalLaunch User
--- autocommand fires before any process spawns, so hooks can prepare audio
--- devices before SuperDirt binds one.
---@param args TidalBootConfig
function M.launch_tidal(args)
  if state.launched then
    notify.warn("Tidal is already running")
    return
  end
  if state.booting then
    vim.notify("[tidal] waiting for SuperDirt...", vim.log.levels.INFO, { title = "Tidal" })
    return
  end

  vim.api.nvim_exec_autocmds("User", { pattern = "TidalLaunch" })

  local sclang_opts = args.sclang
  if sclang_opts and sclang_opts.enabled then
    state.booting = true
    if
      not sclang.boot(sclang_opts, function(ok)
        state.booting = false
        if ok and not state.launched then
          vim.notify("[tidal] SuperDirt ready", vim.log.levels.INFO, { title = "Tidal" })
          start_tidal(args)
        end
      end)
    then
      state.booting = false
    end
    return
  end

  start_tidal(args)
end

function M.start_event_highlighting(args)
  highlight.start(args.highlight)
end

function M.stop_event_highlighting()
  highlight.stop()
end

--- Quit Tidal session
function M.exit_tidal()
  if not state.launched then
    notify.warn("Tidal is not running. Launch with ':TidalLaunch'")
    return
  end

  if state.ghci then
    state.ghci:exit()
  end

  state.launched = false
end

---@return message.TidalRepl
local function ft_to_repl()
  local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  if ft == "haskell" or ft == "tidal" then
    return message.tidal
  end
  -- default to tidal repl
  return message.tidal
end

--- Highlights a sent range and records which pattern blocks it defined.
---@param start { [1]: integer, [2]: integer } {line, col}, zero-indexed
---@param finish { [1]: integer, [2]: integer } {line, col}, zero-indexed
local function mark_sent(start, finish)
  require("tidal.core.highlight").apply_highlight(start, finish)
  require("tidal.highlighting.positions").sent(vim.api.nvim_get_current_buf(), start[1], finish[1])
end

--- Send text to the interpreter for the current filetype
--- @param text string
function M.send(text)
  local repl = ft_to_repl()
  if repl then
    repl.send_line(text)
  end
end

-- Send 'd{count} silence' to tidal interpreter to silence a pattern d1-d16
function M.send_silence()
  message.tidal.send_line(string.format("d%d silence", vim.v.count1))
end

--- Send multiline to the interpreter for the current filetype
--- @param lines string[]
function M.send_multiline(lines)
  local repl = ft_to_repl()
  if repl then
    repl.send_multiline(lines)
  end
end

--- Send the current line to the interpreter for the current filetype
function M.send_line()
  local line = select.get_current_line()
  local text = line.lines[1]
  if #text > 0 then
    mark_sent(line.start, line.finish)
    local repl = ft_to_repl()
    if repl then
      marker.cleanUpMarkers(line.start[1] + 1, line.start[1] + 1)

      repl.send_line(text, line.start)
    end
  end
end

--- Send the last visual selection to the interpreter for the current filetype
function M.send_visual()
  local visual = select.get_visual()
  if visual then
    mark_sent(visual.start, visual.finish)
    local repl = ft_to_repl()
    if repl then
      repl.send_multiline(visual.lines, visual.start)
    end
  end
end

--- Send the current block to the interpreter for the current filetype
function M.send_block()
  if util.is_empty(vim.api.nvim_get_current_line()) then
    return
  end
  local block = select.get_block()
  mark_sent(block.start, block.finish)
  local repl = ft_to_repl()
  if repl then
    repl.send_multiline(block.lines, block.start)
  end
end

--- Send current expression node to the interpreter for the current filetype
function M.send_node()
  local block = select.get_node()
  if block then
    mark_sent(block.start, block.finish)
    local repl = ft_to_repl()
    if repl then
      repl.send_multiline(block.lines)
    end
  end
end

return M
