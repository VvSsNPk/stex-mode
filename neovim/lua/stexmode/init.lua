--- stexmode: sTeX/FLAMS support for Neovim.
---
--- Currently just the Telescope fuzzy symbol-search picker -- a port
--- of stex-mode.el's `stex-mathhub-search-symbols`, not a full port of
--- the Emacs package (see ../README.md for what that would take).

local M = {}

--- Default configuration.  Call `require("stexmode").setup(opts)` to
--- override any of these; other modules always read through
--- `require("stexmode").config` rather than caching a local reference,
--- since `setup()` replaces this table wholesale (a cached reference
--- taken before `setup()` runs would go stale otherwise).
M.config = {
  -- Command used to launch the flams language server.
  cmd = { "flams", "--lsp" },
  -- Directory to launch it in.  Defaults to the cwd; set this if you
  -- want MathHub search available without a .tex buffer open in that
  -- directory already (mirrors stex-mode.el's `stex-mathhub-root`).
  mathhub_root = nil,
  -- Seconds to wait for flams to report its HTTP URL before giving up.
  connect_timeout = 20,
  -- Results requested per query from `api/search_symbols`.
  num_results = 30,
  -- Query length below which no request is sent, to avoid firing on
  -- the very first keystroke of a fresh search.
  min_query_length = 2,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
