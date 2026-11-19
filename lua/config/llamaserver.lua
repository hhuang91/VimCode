-- Lifecycle of the local llama.cpp server that llama.vim completes against.
--
-- llama.vim only speaks HTTP; it neither starts the server nor copes well with
-- it being absent (every keystroke echoes "FIM job failed"). So the plugin is
-- kept disabled until /health answers, and the server is started here if
-- nothing is listening yet.
--
-- The server is spawned detached and deliberately outlives Neovim: loading the
-- model takes seconds, several Neovim instances share one copy of it, and
-- --sleep-idle-seconds hands the VRAM back when nobody is typing.

local M = {}

local uv = vim.uv or vim.loop

M.port = 8012 -- llama.vim's default; the --fim-* presets listen here too

-- Override per machine with vim.g.llama_server_args (a list), e.g. to pick a
-- bigger model. Which GPU to use is better set outside the repo, through the
-- LLAMA_ARG_DEVICE environment variable (see `llama-server --list-devices`).
local default_args = {
  "--fim-qwen-7b-default",
  "--sleep-idle-seconds",
  "1800",
}

local poll_ms = 2000
-- The very first start downloads several GB of weights before it can answer.
local give_up_ms = 30 * 60 * 1000

local spawned = false
local waiting = false

local function base_url()
  return ("http://127.0.0.1:%d"):format(M.port)
end

function M.log_path()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "llama-server.log")
end

---@param cb fun(ok: boolean) called on the main loop
function M.healthy(cb)
  -- 200 {"status":"ok"} once the model is loaded, 503 while it is loading,
  -- connection refused when nothing is listening.
  vim.system({ "curl", "--silent", "--max-time", "1", base_url() .. "/health" }, { text = true }, function(out)
    local ok = out.code == 0 and out.stdout ~= nil and out.stdout:find('"ok"', 1, true) ~= nil
    vim.schedule(function()
      cb(ok)
    end)
  end)
end

local function spawn()
  if spawned then
    return true
  end
  local args = vim.list_extend({}, vim.g.llama_server_args or default_args)
  vim.list_extend(args, { "--port", tostring(M.port), "--log-file", M.log_path() })
  local handle, err = uv.spawn("llama-server", {
    args = args,
    detached = true,
    hide = true, -- no console window on Windows
  }, function() end)
  if not handle then
    vim.notify("llama-server failed to start: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  handle:unref()
  spawned = true
  return true
end

--- Run `on_ready` once the server answers, starting it first if needed.
---@param on_ready fun()
function M.ensure(on_ready)
  if waiting then
    return
  end
  waiting = true
  local started = uv.now()
  local announced = false

  local function check()
    M.healthy(function(ok)
      if ok then
        waiting = false
        if announced then
          vim.notify("llama-server is ready", vim.log.levels.INFO)
        end
        on_ready()
        return
      end
      if not spawned then
        if vim.fn.executable("llama-server") == 0 or not spawn() then
          waiting = false
          return
        end
      end
      local elapsed = uv.now() - started
      if elapsed > give_up_ms then
        waiting = false
        vim.notify("llama-server did not come up; see " .. M.log_path(), vim.log.levels.WARN)
        return
      end
      -- Stay quiet for a normal few-second model load; speak up only when it
      -- drags, which in practice means the first-run download.
      if not announced and elapsed > 15000 then
        announced = true
        vim.notify("Waiting for llama-server (first run downloads the model)…", vim.log.levels.INFO)
      end
      vim.defer_fn(check, poll_ms)
    end)
  end

  check()
end

--- Kill every llama-server on this machine, including one started by hand.
function M.stop()
  local cmd = vim.fn.has("win32") == 1 and { "taskkill", "/F", "/IM", "llama-server.exe" }
    or { "pkill", "-x", "llama-server" }
  vim.system(cmd, {}, function(out)
    spawned = false
    vim.schedule(function()
      vim.notify(out.code == 0 and "llama-server stopped" or "no llama-server was running", vim.log.levels.INFO)
    end)
  end)
end

return M
