--- Telescope picker: fuzzy-search FLAMS's indexed symbols, insert a
--- \usemodule for the one you pick.
---
--- Re-queries `api/search_symbols` on every keystroke (a Telescope
--- "dynamic finder", the same pattern `live_grep` uses for an
--- externally-ranked, re-run-per-prompt source) rather than fetching
--- once and locally fuzzy-filtering, since FLAMS's own index already
--- ranks results server-side across the whole MathHub -- the same
--- design as stex-mode.el's `stex-mathhub-search-symbols`.

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local lsp = require("stexmode.lsp")
local mathhub = require("stexmode.mathhub")
local symbol_uri = require("stexmode.symbol_uri")
local usemodule = require("stexmode.usemodule")

local M = {}

--- Exposed as `M._entry_maker` (an internal, underscore-prefixed
--- export -- not part of the public API, just testable directly
--- without going through Telescope's own interactive picker
--- lifecycle).  `result` is {score, symbol_uri, doc_elem_uri} per
--- `api/search_symbols`'s response shape (1-indexed once decoded from
--- JSON into a Lua table).
function M._entry_maker(result)
  local uri = result[2]
  if type(uri) ~= "string" then
    return nil
  end
  return {
    value = uri,
    display = symbol_uri.label(uri),
    ordinal = symbol_uri.label(uri),
  }
end

--- Build the (dynamic, re-queried-per-keystroke) finder.  Exposed as
--- `M._build_finder` for the same testability reason as
--- `M._entry_maker` -- lets a test grab `.fn`/`.entry_maker` straight
--- off the returned finder object and call them exactly as
--- `telescope.finders.DynamicFinder:_find` itself does internally
--- (confirmed by reading that method's source), without needing to
--- drive Telescope's actual floating-window prompt.
function M._build_finder()
  return finders.new_dynamic({
    fn = function(prompt)
      local config = require("stexmode").config
      if not prompt or #prompt < config.min_query_length then
        return {}
      end
      return mathhub.search_symbols(prompt, config.num_results)
    end,
    entry_maker = M._entry_maker,
  })
end

--- What happens when an entry is picked: resolve its URI to an
--- archive/module-path and insert a \usemodule for it into BUFNR.
--- Exposed as `M._on_select` for the same testability reason as the
--- above.
function M._on_select(entry, bufnr)
  if not entry then
    return
  end
  local archive, module_path = symbol_uri.usemodule_arg(entry.value)
  if not archive or not module_path then
    vim.notify("stexmode: could not parse the chosen symbol's URI", vim.log.levels.ERROR)
    return
  end
  usemodule.insert_usemodule(bufnr, archive, module_path)
end

--- Open the picker.  Ensures a flams connection first (launching a
--- standalone one via `stexmode.lsp` if nothing is connected yet, per
--- `config.mathhub_root`) -- so, same as the Emacs command, this
--- works with no .tex buffer open at all.
function M.search_symbols(opts)
  opts = opts or {}

  local origin_bufnr = vim.api.nvim_get_current_buf()
  local origin_win = vim.api.nvim_get_current_win()

  local ok, err = pcall(lsp.ensure_client)
  if not ok then
    vim.notify("stexmode: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  pickers
    .new(opts, {
      prompt_title = "sTeX symbols (fuzzy)",
      finder = M._build_finder(),
      -- Trust FLAMS's own ranking rather than re-filtering the
      -- already-ranked results locally by fuzzy-matching just the
      -- display label -- same reasoning `live_grep` uses `empty()`
      -- for its own external, per-prompt-re-run source.
      sorter = sorters.empty(),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          vim.api.nvim_set_current_win(origin_win)
          M._on_select(entry, origin_bufnr)
        end)
        return true
      end,
    })
    :find()
end

return M
