return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "super-tab",
      },
      completion = {
        menu = {
          auto_show = function()
            local ft = vim.bo.filetype
            return ft ~= "markdown" and ft ~= "text"
          end,
        },
      },
    },
  },
  -- Inline AI suggestions live in lua/plugins/llama.lua.
}
