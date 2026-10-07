-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--
--
-- Reopen my preferred project side-windows after restoring a session.
-- Works best with:
--   1. cd path/to/project
--   2. nvim
--   3. <leader>qs  -- restore session

local function open_project_layout()
  local project_dir = vim.fn.getcwd()
  -- Open cwd explorer.
  -- LazyVim's Snacks explorer uses Snacks.explorer() for cwd.
  if _G.Snacks and Snacks.explorer then
    local explorer = require("snacks").picker.get({ source = "explorer" })[1]
    if explorer then
    else
      Snacks.explorer({ cwd = project_dir })
    end
  end

  -- Open two bottom terminal panes.
  -- These are plain Neovim terminal buffers, not persistent shell sessions.
  Snacks.terminal.focus(nil, {
    cwd = project_dir,
    count = 1,
  })

  Snacks.terminal.focus(nil, {
    cwd = project_dir,
    count = 2,
  })

  -- escape to normal mode
  vim.cmd("stopinsert")
end

-- Run this after LazyVim/persistence restores a session.
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = function()
    vim.schedule(open_project_layout)
  end,
})
--
-- True when Neovim was launched from the directory its own executable lives in,
-- e.g. the Start menu / desktop shortcut, whose working directory is the `bin/`
-- folder next to nvim.exe. That means "just give me an editor", not a project.
local function launched_from_nvim_bin()
  local exe = vim.v.progpath
  if exe == nil or exe == "" then
    return false
  end
  local bin = vim.fs.normalize(vim.fs.dirname(exe))
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  if vim.fn.has("win32") == 1 then
    bin, cwd = bin:lower(), cwd:lower()
  end
  return cwd == bin
end

-- Run this if we open vim at cwd: restore the session if one exists,
-- otherwise just open the project layout. Skipped when a file was given on the
-- command line, inside a nested Neovim, or when launched from nvim's own bin
-- directory -- those all want a plain editor.
vim.defer_fn(function()
  if vim.fn.argc() ~= 0 or vim.env.NVIM or launched_from_nvim_bin() then
    return
  end
  local persistence = require("persistence")
  local session = persistence.current()
  if vim.fn.filereadable(session) == 0 then
    session = persistence.current({ branch = false })
  end
  if vim.fn.filereadable(session) == 1 then
    persistence.load() -- fires PersistenceLoadPost -> open_project_layout()
  else
    open_project_layout()
  end
end, 100)
