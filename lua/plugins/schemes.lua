return {
  {
    "maxmx03/solarized.nvim",
    lazy = false,
    priority = 1000,
    ---@type solarized.config
    opts = {
      on_highlights = function(colors, color)
        return {
          SpellBad = {
            sp = colors.red,
            undercurl = true,
            strikethrough = false,
          },
          SpellCap = {
            sp = colors.yellow,
            undercurl = true,
            strikethrough = false,
          },
          SpellRare = {
            sp = colors.violet,
            undercurl = true,
            strikethrough = false,
          },
          SpellLocal = {
            sp = colors.cyan,
            undercurl = true,
            strikethrough = false,
          },
        }
      end,
    },
    config = function(_, opts)
      vim.o.termguicolors = true
      vim.o.background = "light"
      require("solarized").setup(opts)
      vim.cmd.colorscheme("solarized")
    end,
  },
}

