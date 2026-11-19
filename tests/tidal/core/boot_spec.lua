local boot = require("tidal.core.boot")
local state = require("tidal.core.state")
local Ghci = require("tidal.repl.ghci")

describe("boot.tidal", function()
  local orig_start

  before_each(function()
    orig_start = Ghci.start
    Ghci.start = function(self)
      return self
    end
    state.ghci = nil
  end)

  after_each(function()
    Ghci.start = orig_start
  end)

  it("a late exit of the previous ghci does not clear the new session", function()
    local opts = { enabled = true, cmd = "ghci", file = "BootTidal.hs" }

    boot.tidal(opts)
    local old = state.ghci
    boot.tidal(opts) -- restart: new session replaces the old one
    local new = state.ghci
    assert.are_not.equal(old, new)

    -- the old process is SIGKILLed after the restart and its exit callback fires late
    old.opts.on_exit(0, 9)
    assert.are.equal(new, state.ghci)

    new.opts.on_exit(0, 15)
    assert.is_nil(state.ghci)
  end)
end)
