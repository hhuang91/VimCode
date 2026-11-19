-- Local inline completion: llama.vim talking to a llama.cpp server on this
-- machine. Replaces GitHub Copilot. See README, "Local AI completion".

local function start()
  require("config.llamaserver").ensure(function()
    vim.fn["llama#enable"]()
  end)
end

return {
  {
    "ggml-org/llama.vim",
    event = "VeryLazy",
    -- Machines without llama.cpp simply get no AI completion. `cond`, not
    -- `enabled`, so the plugin keeps its lazy-lock.json pin either way.
    --
    -- NVIM_NO_LLAMA is the opt-out for a machine that has llama.cpp installed
    -- but should not run a model from the editor (no GPU, too little VRAM).
    -- An environment variable because it is per-machine and so cannot live in
    -- this repo. Any value except empty or "0" counts.
    cond = function()
      local off = vim.env.NVIM_NO_LLAMA
      if off and off ~= "" and off ~= "0" then
        return false
      end
      return vim.fn.executable("llama-server") == 1 and vim.fn.executable("curl") == 1
    end,
    init = function()
      vim.g.llama_config = {
        -- Turned on from `start()` once the server answers.
        enable_at_startup = false,
        show_info = 0, -- no timing stats after the ghost text

        -- <Tab> accepts the whole suggestion, but through blink.cmp's keymap
        -- (see `config` below). llama.vim's own mapping is buffer-local and
        -- un-mapped whenever the hint hides, which would take blink's <Tab>
        -- down with it.
        keymap_fim_accept_full = "",
        keymap_fim_accept_line = "<M-l>",
        keymap_fim_accept_word = "<M-w>",
        -- The default is <leader>llf *in insert mode*, which makes every
        -- space wait out 'timeoutlen'.
        keymap_fim_trigger = "<M-\\>",
        -- Only one candidate is requested (n_cmpl = 1); nothing to cycle.
        keymap_fim_next = "",
        keymap_fim_prev = "",

        -- Instruct mode needs a chat model the server is not running, and its
        -- defaults claim normal-mode <Tab> and <Esc> globally.
        keymap_inst_trigger = "",
        keymap_inst_rerun = "",
        keymap_inst_continue = "",
        keymap_inst_accept = "",
        keymap_inst_cancel = "",
        keymap_debug_toggle = "",
      }

      -- The plugin's default hint colour is bright orange; make it read as
      -- ghost text in every colorscheme.
      local function dim_hint()
        vim.api.nvim_set_hl(0, "llama_hl_fim_hint", { link = "Comment" })
      end
      dim_hint()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = dim_hint })
    end,
    config = function()
      -- LazyVim's blink.cmp <Tab> runs this after "accept the menu item" and
      -- before falling back to a literal tab.
      LazyVim.cmp.actions.ai_accept = function()
        if vim.fn["llama#is_fim_hint_shown"]() then
          LazyVim.create_undo()
          -- blink's mappings are <expr>, where the buffer cannot be changed.
          vim.schedule(function()
            vim.fn["llama#fim_accept"]("full")
          end)
          return true
        end
      end

      vim.api.nvim_create_user_command("LlamaServerStart", start, {
        desc = "Start the local llama.cpp server if needed, then enable llama.vim",
      })
      vim.api.nvim_create_user_command("LlamaServerStop", function()
        vim.fn["llama#disable"]()
        require("config.llamaserver").stop()
      end, { desc = "Disable llama.vim and stop the local llama.cpp server (frees its VRAM)" })

      -- Never from a headless run: scripts/install-* must not load a model.
      if #vim.api.nvim_list_uis() > 0 then
        start()
      end
    end,
  },
}
