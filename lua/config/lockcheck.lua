-- Compare what is checked out under the lazy plugin root against what
-- lazy-lock.json records.
--
-- `:Lazy check` answers a different question: it fetches and compares against
-- the remote branch tip, so it tells you what is *available*, not whether this
-- machine matches the pins the repo ships.
local M = {}

local function read_lock()
  local path = require("lazy.core.config").options.lockfile
  local f = io.open(path, "r")
  if not f then
    return {}, path
  end
  local data = f:read("*a")
  f:close()
  local ok, lock = pcall(vim.json.decode, data)
  return (ok and type(lock) == "table") and lock or {}, path
end

--- States: `drifted` installed at another sha, `missing` in the spec but not
--- installed, `unlocked` installed with no lockfile entry, `orphaned` lockfile
--- entry for a plugin the spec no longer references.
---@return {name:string, want:string?, got:string?, state:string}[], string
function M.diff()
  local Config = require("lazy.core.config")
  local Git = require("lazy.manage.git")
  local lock, path = read_lock()
  local spec = Config.spec or {}
  local disabled, ignored = spec.disabled or {}, spec.ignore_installed or {}
  local seen, rows = {}, {}

  for name, plugin in pairs(Config.plugins) do
    if plugin.url and not plugin._.is_local then
      seen[name] = true
      local entry = lock[name]
      local want = type(entry) == "table" and entry.commit or nil
      -- Git.info reads .git/HEAD directly: no git process, no network.
      local info = plugin._.installed and Git.info(plugin.dir) or nil
      local got = info and info.commit or nil
      local state
      if not got then
        state = "missing"
      elseif not want then
        state = "unlocked"
      elseif got:sub(1, 7) ~= want:sub(1, 7) then
        state = "drifted"
      end
      if state then
        rows[#rows + 1] = { name = name, want = want, got = got, state = state }
      end
    end
  end

  -- lazy keeps entries for disabled/cond plugins on purpose (manage/lock.lua),
  -- so those are not orphans.
  for name, entry in pairs(lock) do
    if not (seen[name] or disabled[name] or ignored[name]) then
      rows[#rows + 1] = {
        name = name,
        want = type(entry) == "table" and entry.commit or nil,
        got = nil,
        state = "orphaned",
      }
    end
  end

  table.sort(rows, function(a, b)
    return a.name < b.name
  end)
  return rows, path
end

---@param opts? {exit?:boolean}
function M.report(opts)
  opts = opts or {}
  local rows, path = M.diff()

  local lines = { "lazy-lock.json: " .. path }
  if #rows == 0 then
    lines[#lines + 1] = "  all plugins match the lockfile"
  end
  for _, r in ipairs(rows) do
    lines[#lines + 1] = ("  %-9s %-32s want %-8s got %s"):format(
      r.state,
      r.name,
      r.want and r.want:sub(1, 8) or "-",
      r.got and r.got:sub(1, 8) or "-"
    )
  end
  local text = table.concat(lines, "\n")

  if #vim.api.nvim_list_uis() == 0 then
    io.stdout:write(text .. "\n")
    -- Opt-in so the plain +LazyLockVerify step in the install scripts still
    -- reaches +qa and does not get reported as a nvim failure.
    if opts.exit then
      os.exit(#rows == 0 and 0 or 1)
    end
  else
    vim.notify(text, #rows == 0 and vim.log.levels.INFO or vim.log.levels.WARN, { title = "LazyLockVerify" })
  end

  return rows
end

return M
