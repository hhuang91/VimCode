-- `:ConfigPull` fast-forwards this config repo from its upstream without leaving
-- Neovim. It touches no plugins: the pulled spec only loads on a restart, and
-- lazy.nvim caches lazy-lock.json in memory, so a `:Lazy restore` in this same
-- session would restore to the pins read at startup, not the ones just pulled.
local M = {}

local LOCK = "lazy-lock.json"
local TITLE = "ConfigPull"

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
end

local function git(root, args, opts, on_exit)
  local cmd = vim.list_extend({ "git", "-C", root }, args)
  return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {}), on_exit)
end

-- Local-only queries; these return in milliseconds, so waiting is fine.
local function run(root, args)
  return git(root, args):wait()
end

local function output(res)
  return vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
end

local DIRTY_NOTE = "lazy-lock.json has local changes (left by :Lazy sync/update?), so :Lazy restore "
  .. "would restore to those instead of the repo's pins. :ConfigPull! discards them."

---@param opts? {discard_lock?:boolean}
function M.pull(opts)
  opts = opts or {}
  local root = vim.fn.stdpath("config")

  if vim.fn.executable("git") == 0 then
    return notify("git is not on PATH", vim.log.levels.ERROR)
  end

  local head = run(root, { "rev-parse", "HEAD" })
  if head.code ~= 0 then
    return notify(root .. " is not a git checkout:\n" .. output(head), vim.log.levels.ERROR)
  end
  local before = vim.trim(head.stdout)

  if opts.discard_lock then
    local res = run(root, { "checkout", "--", LOCK })
    if res.code ~= 0 then
      return notify("Could not discard changes to " .. LOCK .. ":\n" .. output(res), vim.log.levels.ERROR)
    end
  end
  local lock_dirty = run(root, { "status", "--porcelain", "--", LOCK }).stdout ~= ""

  notify("Pulling " .. root .. " ...")

  -- --ff-only: never create a merge commit here; a diverged branch is reported
  -- instead. GIT_TERMINAL_PROMPT=0 fails an HTTPS credential prompt rather than
  -- waiting on a stdin nobody can type into, and the timeout covers an SSH
  -- passphrase prompt, which git has no switch for.
  git(root, { "pull", "--ff-only" }, { timeout = 60000, env = { GIT_TERMINAL_PROMPT = "0" } }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local lines = { "git pull failed:", output(res) }
        if res.code == 124 then
          lines[1] = "git pull timed out after 60s -- is it waiting for a password or SSH passphrase?"
        end
        if lock_dirty then
          lines[#lines + 1] = ""
          lines[#lines + 1] = DIRTY_NOTE
        end
        return notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
      end

      local after = vim.trim(run(root, { "rev-parse", "HEAD" }).stdout)
      local lines, level = {}, vim.log.levels.INFO
      if after == before then
        lines[1] = "Already up to date."
      else
        local log = run(root, { "log", "--oneline", "--no-decorate", before .. ".." .. after })
        local lock_changed = run(root, { "diff", "--name-only", before, after, "--", LOCK }).stdout ~= ""
        lines[1] = ("Updated %s..%s"):format(before:sub(1, 7), after:sub(1, 7))
        lines[2] = vim.trim(log.stdout)
        lines[3] = ""
        lines[4] = lock_changed and "Restart Neovim, then run :Lazy restore to move plugins to the new pins."
          or "Restart Neovim to load the changes."
      end
      if lock_dirty then
        lines[#lines + 1] = ""
        lines[#lines + 1] = DIRTY_NOTE
        level = vim.log.levels.WARN
      end
      notify(table.concat(lines, "\n"), level)
    end)
  end)
end

return M
