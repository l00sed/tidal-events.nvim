local Buffer = require("tidal.util.buffer")

---@class Repl
---@field buf Buffer
---@field proc? integer
---@field opts ReplOpts
---@field onDataProcessed? fun(table<string>)
---@field hushCallback fun()
---@field sendCallback fun()
---@field lockedStdOut table<string>
local Repl = {}
Repl.__index = Repl

---@class ReplOpts
---@field cmd string
---@field args? table<string> additional arguments to for GHCi
---@field name? string repl buffer name
---@field on_exit fun(code: number, signal: number)?

--- Create a new REPL
--- @generic T - generic type for type inference on child 'classes'
--- @param self T
--- @param opts? ReplOpts
--- @return T for method chaining
function Repl:new(opts)
  opts = opts or {}
  local obj = {}
  setmetatable(obj, self)
  obj.opts = opts
  obj.stdout = {}
  obj.stderr = {}
  obj.stdin = {}
  obj.proc = nil
  obj.lockedStdOut = {}

  self.sendCallback = function() end
  self.hushCallback = function() end

  return obj
end

local uv, api, _ = vim.loop, vim.api, vim.fn

local marker = require("tidal.highlighting.marker")
local tokenizer = require("tidal.highlighting.tokenizer")

function Repl:attach(pipe, label)
  local buf_acc = ""
  local isLocked = false

  pipe:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify(("[tidal-fast] %s error: %s"):format(label, err), vim.log.levels.ERROR)
      end)
      return
    end
    if not data then
      return
    end

    vim.schedule(function()
      buf_acc = buf_acc .. data
      local lines = vim.split(buf_acc, "\n", { plain = true })
      local complete, remainder = {}, ""

      if buf_acc:sub(-1) == "\n" then
        if #lines > 0 and lines[#lines] == "" then
          table.remove(lines)
        end
        complete, buf_acc = lines, ""
      else
        remainder = table.remove(lines)
        complete, buf_acc = lines, remainder
      end

      -- ghci runs headless (pipe mode), so surface errors or a failed
      -- evaluation is indistinguishable from silence. Match GHC's error header
      -- ("<interactive>:12:5: error: …"), not the word "error": warnings such as
      -- -Wx-partial say "it throws an error on empty lists".
      if label == "stderr" then
        local text = table.concat(complete, "\n")
        if text:match(":%d+:%d+: error") or text:match("^%s*%*%*%* Exception") then
          vim.notify("[tidal] " .. text:sub(1, 800), vim.log.levels.ERROR, { title = "Tidal" })
        end
      end

      for _, line in ipairs(complete) do
        if line:sub(-#"_START") == "_START" then
          isLocked = true
        end
      end

      if isLocked then
        for _, line in ipairs(complete) do
          table.insert(self.lockedStdOut, line)

          if line:sub(-#"_END") == "_END" then
            self.onDataProcessed(self.lockedStdOut)
            self.lockedStdOut = {}
            isLocked = false
          end
        end
      else
        if self.buf then
          for _, line in ipairs(complete) do
            self.buf:append(line .. "\n")
          end
        end
      end
    end)
  end)
end

--- Start the REPL
--- @param opts table|nil Window options
---  - split: string|nil - Split type ('', 'v', 'h')
---  - win: number|nil - Window to use (default: current window)
--- @generic T
--- @return T for method chaining
function Repl:start(opts)
  if self.proc and self.proc:is_active() then
    return vim.notify("[repl] Command " .. self.opts.cmd .. "already running", vim.log.levels.INFO)
  end

  self.opts = vim.tbl_deep_extend("force", {}, self.opts, opts or {})

  self.stdin = uv.new_pipe(false)
  self.stdout, self.stderr = uv.new_pipe(false), uv.new_pipe(false)

  local handle
  handle = uv.spawn(
    self.opts.cmd,
    { args = self.opts.args, stdio = { self.stdin, self.stdout, self.stderr } },
    function(code, signal)
      for _, p in ipairs({ self.stdin, self.stdout, self.stderr, handle }) do
        if p and not p:is_closing() then
          p:close()
        end
      end
      if self.proc == handle then
        self.proc = nil
      end
      vim.schedule(function()
        vim.notify(("[tidal] ghci exited (code=%d, signal=%d)"):format(code, signal), vim.log.levels.WARN)
        if self.opts.on_exit then
          self.opts.on_exit(code, signal)
        end
      end)
    end
  )
  self.proc = handle

  if not self.proc then
    return vim.notify("[tidal] failed to spawn " .. self.opts.cmd, vim.log.levels.ERROR)
  end

  -- Tidal's ghci does NOT exit on stdin EOF (Ableton Link threads keep the RTS alive),
  -- so quitting Neovim without :TidalQuit used to orphan it — still playing, still holding
  -- port 6010. Kill it synchronously on the way out.
  api.nvim_create_autocmd("VimLeavePre", {
    group = api.nvim_create_augroup("TidalReplCleanup", { clear = true }),
    callback = function()
      self:kill(true)
    end,
  })

  vim.notify("[tidal] " .. self.opts.cmd .. " started (pipe mode)", vim.log.levels.INFO)

  self:attach(self.stdout, "stdout")
  self:attach(self.stderr, "stderr")

  return self
end

function Repl:showNotificationBuffer(filetype)
  if self.buf == nil then
    self.buf = Buffer.new({
      name = self.opts.name,
      scratch = true,
      listed = false,
    })
  end

  self.buf:show(self.opts or {})

  self.buf:set_option("filetype", filetype)
end

--- Send text to REPL
--- @generic T
--- @return T for method chaining
function Repl:send(text, start)
  if start then
    local enrichedText = {}
    local rowIndex = 0
    local rowStart = start[1] + 1

    -- keep blank lines: they still occupy a buffer row, and skipping them
    -- shifts every following line's markers onto the wrong row
    for line in vim.gsplit((text:gsub("\r", ""):gsub("\n$", "")), "\n", { plain = true }) do
      local enrichedLine = line:match("^%s*$") and line or tokenizer.addMetadata(line, rowStart + rowIndex)
      table.insert(enrichedText, enrichedLine)
      rowIndex = rowIndex + 1

      if line:match("^hush") ~= nil then
        marker.deleteAllMarkers()
        tokenizer.lastEventId = tokenizer.eventIdBase

        vim.api.nvim_exec_autocmds("User", { pattern = "TidalHush", modeline = false })
      end
    end

    text = table.concat(enrichedText, "\n") .. "\n"
  end

  -- vim.notify("[tidal-fast] Repl send received", vim.log.levels.INFO)
  if self.stdin and not self.stdin:is_closing() then
    self.stdin:write(text)

    self.sendCallback()
  end

  if self.proc == nil then
    -- not running - error?
    return self
  end

  --vim.api.nvim_chan_send(self.proc, text)
  --self.buf:scroll_to_bottom()
  return self
end

--- Send line of text to REPL
---@param text string
--- @generic T
--- @return T for method chaining
function Repl:send_line(text, start)
  return self:send(text .. "\n", start)
end

--- Send multi-line text to REPL
--- @param lines string[]
--- @generic T
--- @return T for method chaining
function Repl:send_multiline(lines, start)
  return self:send_line(table.concat(lines, "\n"), start)
end

--- Connect to an existing remote ghci process
--- @param remote TidalRemote
--- @generic T
--- @return T for method chaining
function Repl:connect_remote(remote)
  if not remote.unix then
    vim.notify("[tidal] remote requires .unix", vim.log.levels.ERROR)
    return self
  end
  self.stdin = uv.new_pipe(false)
  self.stdin:connect(remote.unix, function(err)
    if err then
      vim.schedule(function()
        vim.notify(("[tidal] failed to connect to %s: %s"):format(remote.unix, err), vim.log.levels.ERROR)
      end)
      return
    end
    self:attach(self.stdin, "io")
    vim.schedule(function()
      vim.notify(("[tidal] connected to %s"):format(remote.unix), vim.log.levels.INFO)
    end)
  end)
  return self
end

--- SIGTERM the process, escalating to SIGKILL if it's still alive after 1 s.
--- The handle is closed by the spawn exit callback, not here: closing it early
--- drops the exit notification (no reap, no on_exit, no escalation possible).
--- @param sync boolean block until the process is gone (for VimLeavePre)
function Repl:kill(sync)
  local proc = self.proc
  if not proc or proc:is_closing() then
    return
  end
  proc:kill("sigterm")

  local function gone()
    return self.proc ~= proc or proc:is_closing()
  end

  if sync then
    vim.wait(1000, gone, 20)
    if not gone() then
      proc:kill("sigkill")
      vim.wait(500, gone, 20)
    end
    return
  end

  local timer = uv.new_timer()
  timer:start(1000, 0, function()
    timer:close()
    if not gone() then
      proc:kill("sigkill")
    end
  end)
end

--- Close the REPL
--- @return self for method chaining
function Repl:exit()
  if self.buf ~= nil then
    self.buf:delete()
  end

  if self.proc and not self.proc:is_closing() then
    self:kill(false)
    vim.notify(string.format("[tidal] %s stopped", self.opts.cmd))
  elseif self.stdin and not self.stdin:is_closing() then
    -- in spawn mode self.stdin gets closed by start()'s on_exit
    -- handler; in remote mode we have to handle it ourselves
    self.stdin:close()
    vim.notify("[tidal] disconnected from remote")
  end

  return self
end

return Repl
