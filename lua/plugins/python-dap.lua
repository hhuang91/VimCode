return {
  {
    "mfussenegger/nvim-dap-python",
    config = function()
      local registry = require("mason-registry")
      local debugpy = registry.get_package("debugpy")
      local path = debugpy:get_install_path()

      local python
      if vim.fn.has("win32") == 1 then
        python = path .. "\\venv\\Scripts\\python.exe"
      else
        python = path .. "/venv/bin/python"
      end

      require("dap-python").setup(python)
    end,
  },
}
