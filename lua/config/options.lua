-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
if vim.fn.has("win32") == 1 then
  local pwsh = [[C:\Program Files\PowerShell\7\pwsh.exe]]
  if vim.fn.executable(pwsh) == 1 then
    LazyVim.terminal.setup("pwsh.exe")
  else
    LazyVim.terminal.setup("powershell.exe")
  end
end

vim.g.autoformat = false

-- Use Astral ty instead of Pyright for Python LSP
-- Remember to install ty via `uv tool install ty`
vim.g.lazyvim_python_lsp = "ty"

-- Keep Ruff as the Python linter/formatter LSP
vim.g.lazyvim_python_ruff = "ruff"

-- Prevent markdown preview from auto closing
-- when switching to another buffer
vim.g.mkdp_auto_close = 0
