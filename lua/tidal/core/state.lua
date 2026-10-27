---@class TidalState
local state = {
  ---@type boolean
  launched = false,
  ---@type Ghci?
  ghci = nil,
  ---@type boolean true while SuperDirt is booting
  booting = false,
}

return state
