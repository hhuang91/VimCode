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
  {
    "zbirenbaum/copilot.lua",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = false, -- Or your preferred key to accept the whole line
          accept_word = "<M-w>", -- Maps Alt+w to accept the next word
          accept_line = "<M-l>", -- Maps Alt+l to accept the whole line
          -- next = "<M-]>",
          -- prev = "<M-[>",
          -- dismiss = "<C-]>",
        },
      },
    },
  },
}
