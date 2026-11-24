-- Inline completion from a llama.cpp server. llama.vim does the editing side;
-- lua/config/llamaserver.lua knows where the server is and decides when to
-- talk to it. Replaces GitHub Copilot. See README, "Local AI completion".

return {
  {
    "ggml-org/llama.vim",
    event = "VeryLazy",
    -- llama.vim shells out to curl for every request and complains at startup
    -- without it. `cond`, not `enabled`, so the plugin keeps its
    -- lazy-lock.json pin either way.
    cond = function()
      return vim.fn.executable("curl") == 1
    end,
    init = function()
      local server = require("config.llamaserver")
      vim.g.llama_config = {
        endpoint_fim = server.url .. "/infill",
        endpoint_inst = server.url .. "/v1/chat/completions",
        api_key = server.api_key or "",
        -- Turned on from `config` below, and only once the server has answered.
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
      local server = require("config.llamaserver")

      local function enable()
        vim.fn["llama#enable"]()
      end

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

      vim.api.nvim_create_user_command("LlamaConnect", function()
        server.connect(enable)
      end, { desc = "Turn suggestions on if the llama.cpp server at NVIM_LLAMA_URL answers" })
      vim.api.nvim_create_user_command("LlamaServerStart", function()
        server.start(enable)
      end, { desc = "Launch a local llama.cpp server unless one answers already, then turn suggestions on" })
      vim.api.nvim_create_user_command("LlamaServerStop", function()
        -- llama#disable() throws unless llama#enable() has run at some point.
        if vim.fn.exists("#llama") == 1 then
          vim.fn["llama#disable"]()
        end
        server.stop()
      end, { desc = "Turn suggestions off and stop the local llama.cpp server, freeing its memory" })

      -- Never from a headless run: scripts/install-* must not go looking for
      -- a server, let alone launch one.
      if #vim.api.nvim_list_uis() > 0 then
        server.startup(enable)
      end
    end,
  },
}
