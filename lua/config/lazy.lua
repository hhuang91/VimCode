local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local lockpath = vim.fn.stdpath("config") .. "/lazy-lock.json"

-- The starter's failure path calls getchar(), which blocks forever under
-- --headless -- which is exactly how scripts/install-* run this file.
local function die(chunks)
  vim.api.nvim_echo(chunks, true, {})
  if #vim.api.nvim_list_uis() > 0 then
    vim.fn.getchar()
  end
  os.exit(1)
end

-- lazy.nvim is the one plugin that cannot pin itself: it has to exist before it
-- can read its own lockfile. Without this it clones whatever `stable` points at
-- on install day, so the tool that enforces every other pin is itself unpinned.
local function locked_commit()
  local f = io.open(lockpath, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  local ok, lock = pcall(vim.json.decode, data)
  if not ok or type(lock) ~= "table" then
    return nil
  end
  local entry = lock["lazy.nvim"]
  if type(entry) ~= "table" or type(entry.commit) ~= "string" then
    return nil
  end
  -- This goes straight into a git argument list; refuse anything but a sha.
  return entry.commit:match("^%x+$") and entry.commit or nil
end

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  -- No --single-branch: the default refspec fetches every branch, so any commit
  -- the lockfile can name is already local and the checkout costs no round trip.
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    die({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    })
  end

  local commit = locked_commit()
  if commit then
    out = vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
    if vim.v.shell_error ~= 0 then
      -- Force-pushed away, or a lockfile newer than this remote. Ask for the sha
      -- directly, then retry.
      vim.fn.system({ "git", "-C", lazypath, "fetch", "--quiet", "--filter=blob:none", "origin", commit })
      if vim.v.shell_error == 0 then
        out = vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
      end
      if vim.v.shell_error ~= 0 then
        -- Not fatal, the stable tag still works. Say so loudly: this is the one
        -- thing that makes a bootstrap non-reproducible.
        vim.api.nvim_echo({
          { "lazy.nvim: could not pin to " .. commit:sub(1, 8) .. ", staying on the stable tag\n", "WarningMsg" },
          { out, "WarningMsg" },
        }, true, {})
      end
    end
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- Versions come from lazy-lock.json; bump pins deliberately with `:Lazy update`
  -- followed by a commit. Leaving the checker on costs an hourly background fetch
  -- of every plugin remote and leaves `:Lazy` permanently offering an update.
  checker = { enabled = false },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

-- Registered here rather than in autocmds.lua/keymaps.lua: LazyVim only sources
-- those on VeryLazy, which may never fire in a headless `+qa` run.
vim.api.nvim_create_user_command("LazyLockVerify", function()
  require("config.lockcheck").report()
end, { desc = "Report plugins whose checked-out commit differs from lazy-lock.json" })
