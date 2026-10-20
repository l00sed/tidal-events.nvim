--- Relays raw terminal output from an external process (e.g. ghostty-audio's
--- palette updates) to the host terminal through Neovim's own UI, so it is
--- serialized with Neovim's redraws instead of racing them on the tty.
---
--- Listens for UDP datagrams; each datagram's payload is sent verbatim with
--- nvim_ui_send() (wrapped in tmux passthrough when running inside tmux).
--- The palette is reset to its configured defaults when Neovim exits.
local Relay = {}

local uv = vim.uv
local sock = nil
local augroup = vim.api.nvim_create_augroup("TidalRelay", { clear = true })

local function wrap(data)
  if vim.env.TMUX then
    return "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
  end
  return data
end

local function send(data)
  pcall(vim.api.nvim_ui_send, wrap(data))
end

--- @param conf { ip: string, port: integer }
function Relay.launch(conf)
  if sock or not vim.api.nvim_ui_send then
    return
  end
  local udp = uv.new_udp()
  if not udp or not udp:bind(conf.ip, conf.port) then
    -- Another Neovim already relays on this port.
    if udp then
      udp:close()
    end
    return
  end
  sock = udp

  if vim.env.TMUX and vim.env.TMUX_PANE then
    vim.system({ "tmux", "set", "-p", "-t", vim.env.TMUX_PANE, "allow-passthrough", "all" })
  end

  sock:recv_start(function(err, data)
    if not err and data then
      vim.schedule(function()
        send(data)
      end)
    end
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      Relay.stop()
    end,
  })
end

function Relay.stop()
  if sock then
    sock:recv_stop()
    sock:close()
    sock = nil
    -- OSC 104 without arguments resets the whole palette to its defaults.
    send("\27]104\27\\")
  end
  vim.api.nvim_clear_autocmds({ group = augroup })
end

return Relay
