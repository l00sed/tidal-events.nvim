--- Publishes the on-screen rectangles of Tidal pattern blocks over OSC, so external
--- visualizers (e.g. a terminal shader drawing each pattern's waveform behind its
--- code) can follow them through scrolling, folds and splits.
---
--- A block starts at a line beginning with `dN` (d1 $ ..., d12 $ ...) and runs until
--- the next blank line or the next `dN` line.
---
--- Message `/tidal/blocks`, sent every highlight frame:
---   s  tmux pane id ($TMUX_PANE), or outside tmux the host terminal device
---      (e.g. /dev/ttys003) so its pixel size can be read; "" if unknown
---   i  editor lines, i editor columns
---   then per visible block: i pattern id (d1 -> 1), i top screen row, i bottom
---   screen row (inclusive), i left screen col, i width in cells (0-based, editor grid)
local Positions = {}

local losc = require("losc.src.losc")
local pluginLibUv = require("losc.src.losc.plugins.udp-libuv")

local osc = nil
local target = "" -- tmux pane id or host terminal device

--- The terminal Neovim's UI runs in: tmux pane, or the TUI process's tty
--- (the server is a child of the TUI since Neovim 0.10).
local function findTarget()
  if vim.env.TMUX_PANE then
    return vim.env.TMUX_PANE
  end
  local tty = vim.trim(vim.fn.system({ "ps", "-o", "tty=", "-p", tostring(vim.uv.os_getppid()) }))
  if vim.v.shell_error == 0 and tty ~= "" and not tty:match("%?") then
    return "/dev/" .. tty
  end
  return ""
end
local augroup = vim.api.nvim_create_augroup("TidalPositions", { clear = true })
local cache = {} -- buf -> { tick = changedtick, blocks = ... }

--- @param conf { ip: string, port: integer }
function Positions.launch(conf)
  osc = losc.new({ plugin = pluginLibUv.new({ sendAddr = conf.ip, sendPort = conf.port }) })
  target = findTarget()
  -- The highlight timer alone (its fps) lets visualizers trail fast scrolling,
  -- so also publish as soon as the view or layout changes.
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "BufWinEnter", "TextChanged", "TextChangedI" }, {
    group = augroup,
    callback = function()
      Positions.publish()
    end,
  })
end

function Positions.stop()
  osc = nil
  vim.api.nvim_clear_autocmds({ group = augroup })
end

--- Pattern blocks of a buffer as { id, first, last } (1-based, inclusive),
--- re-parsed only when the buffer changes.
--- @param buf integer
--- @return { [1]: integer, [2]: integer, [3]: integer }[]
local function patternBlocks(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local hit = cache[buf]
  if hit and hit.tick == tick then
    return hit.blocks
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local blocks, current = {}, nil
  for lnum, line in ipairs(lines) do
    local id = line:match("^d(%d+)%f[^%w_']")
    if id or line:match("^%s*$") then
      if current then
        table.insert(blocks, current)
        current = nil
      end
    end
    if id then
      current = { tonumber(id), lnum, lnum }
    elseif current then
      current[3] = lnum
    end
  end
  if current then
    table.insert(blocks, current)
  end
  cache[buf] = { tick = tick, blocks = blocks }
  return blocks
end

--- Screen rows (0-based) of the visible part of lines first..last in a window.
local function visibleRows(win, first, last)
  local top, bottom = nil, nil
  for lnum = first, last do
    local pos = vim.fn.screenpos(win, lnum, 1)
    if pos.row > 0 then
      top = top or pos.row - 1
      bottom = pos.row - 1
    end
  end
  return top, bottom
end

function Positions.publish()
  if not osc then
    return
  end

  local types = { "s", "i", "i" }
  local args = { target, vim.o.lines, vim.o.columns }

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "tidal" then
      local info = vim.fn.getwininfo(win)[1]
      local left, width = info.wincol - 1 + info.textoff, info.width - info.textoff
      local w0, w1 = info.topline, info.botline
      for _, block in ipairs(patternBlocks(buf)) do
        local id, first, last = block[1], block[2], block[3]
        if last >= w0 and first <= w1 then
          local top, bottom = visibleRows(win, math.max(first, w0), math.min(last, w1))
          if top then
            vim.list_extend(types, { "i", "i", "i", "i", "i" })
            vim.list_extend(args, { id, top, bottom, left, width })
          end
        end
      end
    end
  end

  args.address = "/tidal/blocks"
  args.types = table.concat(types)
  pcall(osc.send, osc, losc.new_message(args))
end

return Positions
