return {
    {
      "hhuang91/yfp.nvim",
      name = "yfp.nvim",
      cmd = "YFP",
      keys = {
        { "<leader>fy", function() require("yfp").open() end, desc = "Yank file path (yfp)" },
      },
      opts = {},
    },
  }
