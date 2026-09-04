return {
  {
    "folke/snacks.nvim",
    init = function()
      -- Workaround: snacks explorer git watcher doesn't reliably detect external
      -- git operations (known issue #1630/#2030). Use Tree:refresh(git_root) to
      -- force full tree + git cache invalidation.
      local function refresh_explorer_git()
        local ok, snacks = pcall(require, "snacks")
        if not ok or not snacks.picker then
          return
        end
        local Tree = require("snacks.explorer.tree")
        for _, picker in ipairs(snacks.picker.get({ source = "explorer" })) do
          if not picker.closed then
            local git_root = Snacks.git.get_root(picker:cwd()) or picker:cwd()
            Tree:refresh(git_root)
            picker.list:set_target()
            picker:find()
          end
        end
      end

      vim.api.nvim_create_autocmd("FocusGained", {
        group = vim.api.nvim_create_augroup("explorer_git_refresh", { clear = true }),
        callback = refresh_explorer_git,
      })

      vim.api.nvim_create_autocmd("TermClose", {
        group = vim.api.nvim_create_augroup("explorer_git_refresh_term", { clear = true }),
        callback = function(ev)
          if vim.api.nvim_buf_get_name(ev.buf):find("lazygit", 1, true) then
            vim.schedule(refresh_explorer_git)
          end
        end,
      })
    end,
  },
}
