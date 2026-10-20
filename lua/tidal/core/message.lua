local state = require("tidal.core.state")

local M = {}

---@class message.TidalRepl
M.tidal = {}

--- Send text to the tidal interpreter
---@param text string
function M.tidal.send(text)
  if not state.ghci then
    return
  end
  require("tidal.highlighting.positions").sentText(vim.split(text, "\n"))
  state.ghci:send(text)
end

--- Send a line of text to the tidal interpreter
---@param text string
function M.tidal.send_line(text, start)
  if not state.ghci then
    return
  end

  require("tidal.highlighting.positions").sentText({ text })
  state.ghci:send_line(text, start)
end

--- Send multiline text to the tidal interpreter
---@param lines string[]
function M.tidal.send_multiline(lines, start)
  if not state.ghci then
    return
  end
  require("tidal.highlighting.positions").sentText(lines)
  state.ghci:send_multiline(lines, start)
end

return M
