local Repl = require("tidal.repl.repl")
local marker = require("tidal.highlighting.marker")

---@class Ghci : Repl
local Ghci = Repl:new()
Ghci.__index = Ghci

--- Split lines into blank-line separated blocks.
---@param lines string[]
---@return { offset: integer, lines: string[] }[]
function Ghci.split_blocks(lines)
  local blocks, current = {}, nil
  for i, line in ipairs(lines) do
    if line:match("^%s*$") then
      current = nil
    else
      if not current then
        current = { offset = i - 1, lines = {} }
        table.insert(blocks, current)
      end
      table.insert(current.lines, line)
    end
  end
  return blocks
end

--- Send multi-line text to GHCi. A selection spanning several blank-line
--- separated blocks (e.g. d1 … d6) is sent as one :{ :} per block, since GHCi
--- parses a single :{ :} as one statement.
---@param lines string[]
function Ghci:send_multiline(lines, start)
  if start then
    marker.setRemovables(start[1], start[1] + #lines)
  end
  for _, block in ipairs(Ghci.split_blocks(lines)) do
    local text = ":{\n" .. table.concat(block.lines, "\n") .. "\n:}"
    self:send_line(text, start and { start[1] + block.offset - 1, start[2] } or nil)
  end
  return self
end

return Ghci
