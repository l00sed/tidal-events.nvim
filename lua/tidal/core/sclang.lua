local notify = require("tidal.util.notify")

---@class TidalSclangConfig
---@field cmd string command to launch SuperCollider (boot file is appended)
---@field file string|nil path to the SuperDirt boot file; required when enabled
---@field args table<string>
---@field enabled boolean
---@field wait integer seconds to wait for the ready file before giving up
---@field ready_file string|nil file written by the boot file once SuperDirt is up; nil = no readiness check

local M = {}

local TICK = 100 -- ms between readiness polls

---Is a SuperDirt (sclang) process already running with this boot file?
---@param file string
---@return boolean
function M.is_running(file)
  if vim.fn.executable("pgrep") == 0 then
    return false
  end
  vim.fn.system({ "pgrep", "-f", file })
  return vim.v.shell_error == 0
end

---@param opts TidalSclangConfig
---@param attempt integer
---@param done fun(ok: boolean)
local function wait_for_ready(opts, attempt, done)
  local file = vim.fn.expand(opts.ready_file)
  if vim.fn.filereadable(file) == 1 then
    vim.api.nvim_exec_autocmds("User", { pattern = "TidalSuperDirtReady", modeline = false })
    return done(true)
  end
  if attempt >= (opts.wait or 60) * (1000 / TICK) then
    notify.warn(
      ("SuperDirt not ready after %ds — check the sclang output, then run :TidalLaunch to retry"):format(
        opts.wait or 60
      )
    )
    return done(false)
  end
  vim.defer_fn(function()
    wait_for_ready(opts, attempt + 1, done)
  end, TICK)
end

---Boot SuperDirt (detached, so it keeps playing after Neovim exits), then call
---done(ok) once it is ready. Reuses an sclang process already running with the
---same boot file instead of spawning a second one.
---@param opts TidalSclangConfig
---@param done fun(ok: boolean)
---@return boolean started false when booting could not begin (no orphan callbacks)
function M.boot(opts, done)
  local file = vim.fn.expand(opts.file or "")
  if file == "" then
    notify.error("boot.sclang.enabled = true but boot.sclang.file is not set")
    return false
  end
  if vim.fn.filereadable(file) == 0 then
    notify.error(("boot.sclang.file not found: %s"):format(file))
    return false
  end

  if M.is_running(file) then
    vim.notify("[tidal] reusing running SuperDirt", vim.log.levels.INFO, { title = "Tidal" })
  else
    -- A ready file left behind by a crashed sclang would make the readiness
    -- poll below pass immediately with nothing listening on /dirt.
    if opts.ready_file then
      pcall(vim.fn.delete, vim.fn.expand(opts.ready_file))
    end
    local args = vim.list_extend(vim.deepcopy(opts.args or {}), { file })
    local job_id = vim.fn.jobstart(vim.list_extend({ opts.cmd }, args), { detach = true })
    if not job_id or job_id == 0 then
      notify.error(("failed to spawn %s"):format(opts.cmd))
      return false
    end
    vim.notify(
      ("[tidal] sclang started (detached): %s %s"):format(opts.cmd, file),
      vim.log.levels.INFO,
      { title = "Tidal" }
    )
  end

  if not opts.ready_file then
    -- No readiness signal configured; assume SuperDirt will be up by send time.
    vim.api.nvim_exec_autocmds("User", { pattern = "TidalSuperDirtReady", modeline = false })
    vim.schedule(function()
      done(true)
    end)
    return true
  end

  vim.defer_fn(function()
    wait_for_ready(opts, 0, done)
  end, TICK)
  return true
end

return M
