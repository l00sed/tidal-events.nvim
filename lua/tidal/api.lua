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

---Poll until no sclang process with this boot file is running (max ~2 s).
---@param file string expanded boot file path
---@param attempt integer
---@param done fun()
local function wait_sclang_gone(file, attempt, done)
  if attempt >= 20 or not sclang.is_running(file) then
    return done()
  end
  vim.defer_fn(function()
    wait_sclang_gone(file, attempt + 1, done)
  end, 100)
end

---Restart the Tidal session with a clean SuperDirt boot. sclang is detached
---and binds its audio output device when it boots, so an instance left over
---from an earlier session keeps playing into whatever device existed then
---(renamed device, recreated aggregate...) — audible silence. TidalRestart
---hushes, quits the REPL, kills leftover SuperDirt processes and launches
---fresh through the normal launch path (the TidalLaunch autocommand fires).
---@param args TidalBootConfig
function M.restart_tidal(args)
  if state.booting then
    notify.warn("SuperDirt boot already in progress")
    return
  end

  if state.launched then
    pcall(message.tidal.send_line, "hush", { 0, 0 })
    vim.api.nvim_exec_autocmds("User", { pattern = "TidalHush", modeline = false })
    if state.ghci then
      state.ghci:exit()
    end
    state.launched = false
  end

  local sclang_opts = args.sclang
  local file = (sclang_opts and sclang_opts.enabled and sclang_opts.file) and vim.fn.expand(sclang_opts.file) or nil
  if file and sclang.is_running(file) then
    vim.fn.system({ "pkill", "-f", file })
  end

  local function launch()
    if file then
      -- sclang doesn't always keep its scsynth child clean when terminated,
      -- and a second server can't bind port 57110 while one lingers.
      vim.fn.system({ "pkill", "-x", "scsynth" })
    end
    vim.defer_fn(function()
      M.launch_tidal(args)
    end, 300)
  end

  if file then
    wait_sclang_gone(file, 0, launch)
  else
    launch()
  end
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
