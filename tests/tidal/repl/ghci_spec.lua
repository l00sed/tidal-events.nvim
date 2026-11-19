local Ghci = require("tidal.repl.ghci")
local marker = require("tidal.highlighting.marker")
local lineProcessor = require("tidal.highlighting.lineprocessor")
local tokenizer = require("tidal.highlighting.tokenizer")

local eq = assert.are.same

local buffer_lines = {
  "d1 $ stack [",
  '    s "bd*2",',
  '    s "~ hh"',
  "  ]",
  "",
  '-- a "quoted" comment',
  'd2 $ s "sn:3 ~ sn"',
  "",
  "",
  'd3 $ n "0 .. 7" # s "superpiano"',
}

--- Ghci wired to a fake stdin that records every write
local function fake_ghci()
  local g = Ghci:new({ cmd = "ghci" })
  local writes = {}
  g.stdin = {
    is_closing = function()
      return false
    end,
    write = function(_, text)
      table.insert(writes, text)
    end,
  }
  g.proc = {}
  g.sendCallback = function() end
  return g, writes
end

describe("Ghci", function()
  describe("split_blocks", function()
    it("splits on blank and whitespace-only lines, keeping offsets", function()
      local blocks = Ghci.split_blocks({ "a", "b", "", "c", "   ", "", "d" })
      eq({
        { offset = 0, lines = { "a", "b" } },
        { offset = 3, lines = { "c" } },
        { offset = 6, lines = { "d" } },
      }, blocks)
    end)

    it("returns a single block when there are no blank lines", function()
      eq({ { offset = 0, lines = { "x", "y" } } }, Ghci.split_blocks({ "x", "y" }))
    end)

    it("returns nothing for an all-blank selection", function()
      eq({}, Ghci.split_blocks({ "", "  " }))
    end)
  end)

  describe("send_multiline with several blocks", function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, buffer_lines)
      marker.extMarks = {}
      tokenizer.lastEventId = tokenizer.eventIdBase
    end)

    after_each(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("sends one :{ :} per block (visual selection of d1..d3)", function()
      local g, writes = fake_ghci()
      g:send_multiline(buffer_lines, { 0, 0 })

      -- d1 · (comment + d2) · d3
      eq(3, #writes)
      for _, w in ipairs(writes) do
        assert.is_truthy(w:match("^:{\n"))
        assert.is_truthy(w:match("\n:}\n$"))
      end
      assert.is_truthy(writes[2]:find("d2 $", 1, true))
      assert.is_falsy(writes[2]:find("d1 $", 1, true))
    end)

    it("does not error and puts every marker on the row its text came from", function()
      local g = fake_ghci()
      assert.has_no.errors(function()
        g:send_multiline(buffer_lines, { 0, 0 })
      end)

      local count = 0
      for _, marks in pairs(marker.extMarks) do
        for _, m in pairs(marks) do
          count = count + 1
          local line = buffer_lines[m.row + 1]
          eq(line:sub(m.colStart + 1, m.colEnd), m.originalText)
        end
      end
      assert.is_true(count > 0)
    end)

    it("leaves strings in comments alone", function()
      local g, writes = fake_ghci()
      g:send_multiline(buffer_lines, { 0, 0 })
      local all = table.concat(writes)
      assert.is_truthy(all:find('-- a "quoted" comment', 1, true))
    end)
  end)
end)

describe("lineprocessor.isExcepted", function()
  it("exempts numerals assignments, named patterns and comments", function()
    assert.is_true(lineProcessor.isExcepted("numerals = "))
    assert.is_true(lineProcessor.isExcepted("p "))
    assert.is_true(lineProcessor.isExcepted("-- see "))
  end)

  it("does not exempt ordinary pattern arguments", function()
    assert.is_false(lineProcessor.isExcepted("d1 $ s "))
    assert.is_false(lineProcessor.isExcepted('d1 $ stop $ s "bd" # n '))
  end)
end)
