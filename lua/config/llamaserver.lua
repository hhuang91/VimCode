-- The llama.cpp server behind llama.vim's suggestions: where it is, whether it
-- answers, and -- only when asked to -- starting or stopping one on this
-- machine.
--
-- By default Neovim is a client of that server and nothing more. It connects
-- to NVIM_LLAMA_URL when it starts and leaves suggestions off if nothing
-- answers; which model runs, on which machine, and when it is loaded is up to
-- whoever runs the server. Launching one from here is a convenience behind an
-- explicit command (:LlamaServerStart) or an explicit opt-in
-- (NVIM_LLAMA_AUTOSTART), because a model is several GB of download and of
-- memory that nobody should get just for opening an editor.
--
-- All of it is configured through environment variables: every setting is per
-- machine, and this repo is shared between machines.
--
--   NVIM_LLAMA_URL          base URL of the server (default http://127.0.0.1:8012)
--   NVIM_LLAMA_API_KEY      bearer token, for a server started with --api-key
--   NVIM_LLAMA_AUTOSTART    launch a local server at startup if none answers
--   NVIM_LLAMA_SERVER_ARGS  model arguments for a launched server
--                           (default --fim-qwen-7b-default)
--
-- llama.vim itself only speaks HTTP and copes badly with a server that is not
-- there (every keystroke echoes "FIM job failed"), so the plugin is kept
-- disabled until /health answers.

local M = {}

local uv = vim.uv or vim.loop
local is_win = vim.fn.has("win32") == 1

-- llama.vim's own default, and where llama-server's --fim-* presets listen.
local DEFAULT_URL = "http://127.0.0.1:8012"
local DEFAULT_MODEL_ARGS = { "--fim-qwen-7b-default" }

local POLL_MS = 2000
-- Loading an already-downloaded model takes around 15 s; past this it is news.
local SLOW_MS = 30000
-- A first launch downloads several GB of weights before it can answer.
local GIVE_UP_MS = 30 * 60 * 1000
-- The launch lock is held for a fraction of a second; one older than this was
-- left behind by a Neovim that died holding it.
local LOCK_STALE_S = 30

---@return string? value nil when unset or empty
local function env(name)
  local value = vim.env[name]
  if value ~= nil and value ~= "" then
    return value
  end
end

--- Lenient on purpose: accepts a missing scheme, a trailing slash, and
--- llama.vim's own endpoint (".../infill") pasted in place of the base URL.
---@param raw string
local function parse_url(raw)
  local url = vim.trim(raw)
  if not url:match("^%a[%w+.-]*://") then
    url = "http://" .. url
  end
  url = url:gsub("/+$", "")
  url = url:gsub("/infill$", "")

  local scheme, authority = url:match("^(%a[%w+.-]*)://([^/]*)")
  local host, port
  if authority:sub(1, 1) == "[" then -- IPv6 literal
    host, port = authority:match("^(%[.-%]):?(%d*)$")
  else
    host, port = authority:match("^([^:]*):?(%d*)$")
  end
  scheme, host = scheme:lower(), (host or authority):lower()

  return {
    url = url,
    host = host,
    port = tonumber(port) or (scheme == "https" and 443 or 80),
    -- Only a server this machine could be running: plain http on loopback.
    is_local = scheme == "http"
      and (host == "localhost" or host == "[::1]" or host:match("^127%.%d+%.%d+%.%d+$") ~= nil),
  }
end

--- Split a command line on whitespace, honouring '...' and "..." so a path
--- with spaces survives. Backslashes are left alone (Windows paths).
---@param line string
---@return string[]
local function split_args(line)
  local args, current, quote, pending = {}, {}, nil, false
  local function flush()
    if pending then
      args[#args + 1] = table.concat(current)
      current, pending = {}, false
    end
  end
  for ch in line:gmatch(".") do
    if quote then
      if ch == quote then
        quote = nil
      else
        current[#current + 1] = ch
      end
    elseif ch == '"' or ch == "'" then
      quote, pending = ch, true
    elseif ch:match("%s") then
      flush()
    else
      current[#current + 1] = ch
      pending = true
    end
  end
  flush()
  return args
end

local target = parse_url(env("NVIM_LLAMA_URL") or DEFAULT_URL)
-- An allowlist, so that a value like "false" or a typo never opts a machine in
-- to a multi-GB download.
local autostart = vim.list_contains({ "1", "true", "yes", "on" }, (env("NVIM_LLAMA_AUTOSTART") or ""):lower())
-- Someone set this machine up for a server, so its absence is worth a message.
local configured = autostart or env("NVIM_LLAMA_URL") ~= nil
local raw_args = env("NVIM_LLAMA_SERVER_ARGS")
local model_args = raw_args and split_args(raw_args) or DEFAULT_MODEL_ARGS

M.url = target.url ---@type string base URL, no trailing slash
M.api_key = env("NVIM_LLAMA_API_KEY") ---@type string?

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "llama.vim" })
end

local function warn(msg)
  notify(msg, vim.log.levels.WARN)
end

--- Per port, so that servers for two different URLs never share a file.
---@param ext "log"|"pid"|"lock"
local function state_file(ext)
  return vim.fs.joinpath(vim.fn.stdpath("state"), ("llama-server-%d.%s"):format(target.port, ext))
end

--- Where a server launched from here writes its log.
function M.log_path()
  return state_file("log")
end

---@param cmd string[]
---@param cb fun(stdout: string) empty when the command failed
local function capture(cmd, cb)
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      cb(out.code == 0 and out.stdout or "")
    end)
  end)
end

--- Whether `pid` is a running llama-server, going by its name. Checked before
--- trusting a remembered pid and before killing anything.
---@param pid integer
---@param cb fun(yes: boolean)
local function is_llama_server(pid, cb)
  local cmd = is_win and { "tasklist", "/FI", "PID eq " .. pid, "/FO", "CSV", "/NH" }
    or { "ps", "-p", tostring(pid), "-o", "comm=" }
  capture(cmd, function(out)
    cb(out:lower():find("llama-server", 1, true) ~= nil)
  end)
end

--- Ask /health once.
---@param cb fun(ready: boolean, status: string?) status is the HTTP status, nil when nothing answered at all
function M.probe(cb)
  local cmd = {
    "curl",
    "--silent",
    "--connect-timeout",
    "2",
    "--max-time",
    "3",
    "--output",
    is_win and "NUL" or "/dev/null",
    "--write-out",
    "%{http_code}",
  }
  if M.api_key then
    vim.list_extend(cmd, { "--header", "Authorization: Bearer " .. M.api_key })
  end
  cmd[#cmd + 1] = M.url .. "/health"
  vim.system(cmd, { text = true }, function(out)
    local status = vim.trim(out.stdout or "")
    if out.code ~= 0 or status == "000" or not status:match("^%d%d%d$") then
      status = nil
    end
    vim.schedule(function()
      -- 200 once the model is usable, 503 while llama-server is loading it.
      cb(status == "200", status)
    end)
  end)
end

-- Launching ------------------------------------------------------------------
--
-- Two Neovims that start together must not both launch a server: on Windows
-- the second one binds the same port without complaint and a second copy of
-- the model stays loaded. And a launched server does not open its port until
-- it has downloaded its model, which can take many minutes and outlast the
-- Neovim that launched it. So:
--
--   * the lock file serializes "is one running already? if not, spawn" across
--     Neovim instances, for the fraction of a second that takes;
--   * the pid file remembers the server that was spawned, so a later launch
--     can tell that one is already on its way even though nothing answers yet.

--- Take the launch lock. `false` means another Neovim is launching right now.
local function try_lock()
  local path = state_file("lock")
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd, _, code = uv.fs_open(path, "wx", 420) -- 0644; EEXIST if the file is there
  if fd then
    uv.fs_close(fd)
    return true
  elseif code ~= "EEXIST" then
    return true -- cannot lock at all (read-only state dir?): launching unlocked beats never launching
  end
  -- Clear a stale lock but do not take it in the same breath: it is retaken on
  -- the next poll, so nobody can remove a lock that was created a moment ago.
  local stat = uv.fs_stat(path)
  if stat and os.time() - stat.mtime.sec > LOCK_STALE_S then
    uv.fs_unlink(path)
  end
  return false
end

local function unlock()
  uv.fs_unlink(state_file("lock"))
end

--- The server launched from a Neovim earlier, if it is still running.
---@param cb fun(pid: integer?)
local function launched_server(cb)
  local file = io.open(state_file("pid"), "r")
  local pid = file and tonumber(file:read("*l") or "")
  if file then
    file:close()
  end
  if not pid then
    return cb(nil)
  end
  is_llama_server(pid, function(yes)
    cb(yes and pid or nil)
  end)
end

---@return string? why a clause that completes "nothing answers, and ..."
local function cannot_launch()
  if not target.is_local then
    return "a server can only be launched for a local http:// address"
  end
  if vim.fn.executable("llama-server") == 0 then
    return "llama-server is not on PATH to launch one"
  end
end

-- Exit code of the server spawned by this Neovim, once it has exited.
local spawned_exit ---@type integer?

--- Spawn a detached llama-server for the configured URL.
---@return string? err
local function spawn()
  -- Later arguments win. The idle unload is a default the model arguments may
  -- override; host and port come last because they have to match the URL.
  local args = { "--sleep-idle-seconds", "1800" }
  vim.list_extend(args, model_args)
  vim.list_extend(args, {
    "--host",
    (target.host:gsub("[%[%]]", "")),
    "--port",
    tostring(target.port),
    "--log-file",
    M.log_path(),
  })

  spawned_exit = nil
  local handle, pid
  -- Detached, and deliberately outliving Neovim: loading the model takes a
  -- while, and every Neovim instance on the machine shares the one copy.
  handle, pid = uv.spawn("llama-server", {
    args = args,
    -- Not Neovim's own cwd, which the server would keep pinned (on Windows,
    -- undeletable) for as long as it runs.
    cwd = uv.os_homedir(),
    detached = true,
    hide = true, -- no console window on Windows
  }, function(code)
    spawned_exit = code
    handle:close()
  end)
  if not handle then
    return "llama-server failed to start: " .. tostring(pid)
  end
  handle:unref()

  local file = io.open(state_file("pid"), "w")
  if file then
    file:write(tostring(pid))
    file:close()
  end
end

local waiting = false

---@class LlamaAwaitOpts
---@field launch boolean start a local server if nothing is listening
---@field verbose boolean asked for by command, so report progress and the outcome
---@field on_ready fun()
---@field on_fail fun(why: string)

--- Call `on_ready` once the server answers, or `on_fail` once it is clear that
--- it will not.
---@param opts LlamaAwaitOpts
local function await(opts)
  if waiting then
    if opts.verbose then
      notify("Already waiting for the server at " .. M.url)
    end
    return
  end
  waiting = true
  local started = uv.now()
  local spawned, announced = false, false
  local step

  local function finish(err)
    waiting = false
    if err then
      opts.on_fail(err)
      return
    end
    if opts.verbose or announced then
      notify("Connected to the llama.cpp server at " .. M.url)
    end
    opts.on_ready()
  end

  -- Still coming up: probe again in a moment.
  local function again()
    local elapsed = uv.now() - started
    if elapsed > GIVE_UP_MS then
      return finish(("The server at %s is still not ready"):format(M.url))
    end
    -- Unprompted, stay quiet through an ordinary model load and speak up only
    -- when it drags -- in practice, the first-run download.
    if not announced and (opts.verbose or elapsed > SLOW_MS) then
      announced = true
      notify(
        spawned and "Starting llama-server (a first run downloads the model)…"
          or ("Waiting for the server at %s to finish starting…"):format(M.url)
      )
    end
    vim.defer_fn(step, POLL_MS)
  end

  local function launch()
    local why = cannot_launch()
    if why then
      return finish(("No llama.cpp server answers at %s, and %s"):format(M.url, why))
    end
    if not try_lock() then
      return again() -- another Neovim is in the middle of launching one
    end
    launched_server(function(pid)
      if pid then
        unlock()
        return again() -- launched earlier and still on its way up: wait for that one
      end
      local err = spawn()
      unlock()
      if err then
        return finish(err)
      end
      spawned = true
      again()
    end)
  end

  step = function()
    M.probe(function(ready, status)
      if ready then
        finish()
      elseif status == "503" then
        again() -- a llama-server that is still loading its model
      elseif status then
        -- Something answers, but nothing that waiting will make ready:
        -- another service on that port, or a rejected API key.
        finish(("%s answered HTTP %s on /health"):format(M.url, status))
      elseif spawned and spawned_exit then
        finish(("llama-server exited with code %d before answering; see %s"):format(spawned_exit, M.log_path()))
      elseif spawned then
        again() -- ours has not opened its port yet
      elseif opts.launch then
        launch()
      else
        finish("No llama.cpp server answers at " .. M.url)
      end
    end)
  end

  step()
end

--- Turn suggestions on if the server answers. Never starts one.
---@param on_ready fun()
function M.connect(on_ready)
  await({ launch = false, verbose = true, on_ready = on_ready, on_fail = warn })
end

--- Launch a local server unless one answers already, then turn suggestions on.
---@param on_ready fun()
function M.start(on_ready)
  await({ launch = true, verbose = true, on_ready = on_ready, on_fail = warn })
end

--- What Neovim does by itself at startup: connect, and launch only on opt-in.
---@param on_ready fun()
function M.startup(on_ready)
  await({
    launch = autostart,
    verbose = false,
    on_ready = on_ready,
    on_fail = function(why)
      -- With nothing configured, an unanswered default URL only means this
      -- machine does not use the feature. Say nothing.
      if configured then
        warn(why .. "\n:LlamaConnect tries again.")
      end
    end,
  })
end

-- Stopping -------------------------------------------------------------------

--- Find the processes listening on the configured port.
---@param cb fun(pids: integer[], err: string?)
local function listener_pids(cb)
  local port = tostring(target.port)
  local function unique(found)
    local seen, pids = {}, {}
    for _, pid in ipairs(found) do
      if not seen[pid] then
        seen[pid] = true
        pids[#pids + 1] = pid
      end
    end
    cb(pids)
  end

  if is_win then
    -- A listener is the row whose remote address has port 0. Matched that way
    -- because the state column ("LISTENING") is localized.
    capture({ "netstat", "-ano" }, function(out)
      local found = {}
      for line in out:gmatch("[^\r\n]+") do
        local laddr, raddr, pid = line:match("^%s*TCP%s+(%S+)%s+(%S+)%s+.-%s+(%d+)%s*$")
        if laddr and laddr:match(":" .. port .. "$") and raddr:match(":0$") then
          found[#found + 1] = tonumber(pid)
        end
      end
      unique(found)
    end)
  elseif vim.fn.executable("lsof") == 1 then
    capture({ "lsof", "-nP", "-iTCP:" .. port, "-sTCP:LISTEN", "-t" }, function(out)
      unique(vim.tbl_map(tonumber, vim.split(vim.trim(out), "%s+", { trimempty = true })))
    end)
  elseif vim.fn.executable("ss") == 1 then
    capture({ "ss", "-ltnp", "sport", "=", ":" .. port }, function(out)
      local found = {}
      for pid in out:gmatch("pid=(%d+)") do
        found[#found + 1] = tonumber(pid)
      end
      unique(found)
    end)
  else
    cb({}, "Cannot tell which process listens on port " .. port .. " (needs lsof or ss)")
  end
end

--- Stop the llama-server on the configured port, whoever started it. Other
--- llama-servers on the machine, and anything that is not one, are left alone.
function M.stop()
  if not target.is_local then
    return notify(("%s is not on this machine, so no server was stopped"):format(M.url))
  end
  listener_pids(function(pids, err)
    if #pids == 0 then
      -- Killing is strictly by port. A server that has not opened its port
      -- yet is only reported: a remembered pid is not proof enough to kill.
      return launched_server(function(pid)
        if err then
          notify(err)
        elseif pid then
          local msg = "llama-server (pid %d) is still starting and has not opened port %d yet; left running"
          notify(msg:format(pid, target.port))
        else
          notify(("Nothing is listening on port %d"):format(target.port))
        end
      end)
    end
    for _, pid in ipairs(pids) do
      is_llama_server(pid, function(yes)
        if not yes then
          return warn(("The process on port %d (pid %d) is not llama-server; left alone"):format(target.port, pid))
        end
        local ok, kill_err = uv.kill(pid, "sigterm")
        if ok then
          notify("llama-server stopped")
        else
          warn(("Could not stop llama-server (pid %d): %s"):format(pid, tostring(kill_err)))
        end
      end)
    end
  end)
end

return M
