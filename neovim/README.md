# stexmode.nvim

A Neovim/Lua counterpart to [`stex-mode.el`](../stex-mode.el) -- **not** a
full port. `stex-mode.el` leans heavily on AUCTeX (environment/macro
insertion, fill protection) and Emacs-specific primitives (`make-network-process`
for the live-reload preview relay) that have no equivalent in Neovim's
plugin ecosystem; porting all of that would be a from-scratch rewrite
against entirely different primitives, not a mechanical translation. This
currently covers one piece: **fuzzy MathHub symbol search, as a Telescope
picker** -- a Lua port of `stex-mode.el`'s `stex-mathhub-search-symbols`.

## What it does

`:StexMathhubSearchSymbols` (or `require("telescope").extensions.stexmode.search_symbols()`)
opens a Telescope picker that fuzzy-searches every symbol FLAMS has
indexed across your whole MathHub, live -- it re-queries FLAMS's real
`POST api/search_symbols` endpoint on every keystroke (the same endpoint
`stex-mode.el` uses; see that package's `.claude/CLAUDE.md`, "Fuzzy symbol
search", for how it was found -- it's not a documented REST API, but a
real Leptos server function in FLAMS's own source). Picking a result
inserts a `\usemodule` for that symbol's module at point, same as the
Emacs command.

It connects to `flams` the same way `stex-mode.el` does: reusing an
already-attached `flams` LSP client if one exists (e.g. one
`nvim-lspconfig` already started for the current `.tex` buffer), or
launching a standalone one in `mathhub_root` if nothing is connected yet
-- so this works with no `.tex` buffer open at all, same as the Emacs
side. Either way, it needs `flams` to report its HTTP base URL over its
custom `flams/serverURL` LSP notification before it can search, since
that's a plain HTTP endpoint, not an LSP request.

## Requirements

- Neovim 0.10+ (`vim.lsp.start`, `vim.json.decode`, `client:is_stopped()`).
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) --
  already dependencies of each other, nothing extra to install.
- The `flams` executable on your `PATH` (or configure `cmd` -- see below).

## Installation

With `lazy.nvim`, pointed at this subdirectory of the `stex-mode.el` repo:

```lua
{
  "your-fork-or-local-path/stexmode",
  dir = "/path/to/stexmode/neovim", -- this directory specifically
  dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
  opts = {},
}
```

Or, manually: put this directory (`neovim/`) on your runtimepath (e.g.
symlink it into `~/.local/share/nvim/site/pack/plugins/start/stexmode`),
then call `require("stexmode").setup({...})` from your config.

## Configuration

```lua
require("stexmode").setup({
  -- Command used to launch the flams language server.
  cmd = { "flams", "--lsp" },
  -- Directory to launch it in when nothing's connected yet. Defaults
  -- to the cwd; set this to browse/search MathHub with no .tex buffer
  -- open in that directory already (mirrors stex-mode.el's
  -- `stex-mathhub-root`).
  mathhub_root = nil,
  -- Seconds to wait for flams to report its HTTP URL before giving up.
  connect_timeout = 20,
  -- Results requested per query from `api/search_symbols`.
  num_results = 30,
  -- Query length below which no request is sent, to avoid firing on
  -- the very first keystroke of a fresh search.
  min_query_length = 2,
})
```

## What's not here

Everything else in `stex-mode.el`: build/export commands, the archive/file
drill-down browser, the MathHub tree view, environment/macro insertion
(`C-c C-e`/`C-c C-m`'s AUCTeX integration -- Neovim has no AUCTeX
equivalent to hook into; this would need to be rebuilt against
`nvim-cmp`/`blink.cmp`/`LuaSnip` instead, a different mechanism entirely),
fill protection, local symbol/macro-name completion, the build dashboard,
and the live-reload preview relay. None of it is architecturally hard to
port individually -- see the corresponding sections of `stex-mode.el`'s
own `.claude/CLAUDE.md` for how each one works -- there's just a lot of
it, and each piece needs re-deriving against Neovim's own primitives
(`vim.lsp`, a completion engine, `vim.uv`) rather than a mechanical
Emacs-Lisp-to-Lua translation.

## Testing

There's no `nvim` binary dependency baked into a test runner here (the
functions are plain Lua, easiest to check the way they were developed:
load the modules in a headless `nvim -u NONE`, stub what needs stubbing,
call them directly). Verified during development with:

- Every pure function (`stexmode.util`, `stexmode.symbol_uri`,
  `stexmode.usemodule`) against direct unit tests.
- `stexmode.mathhub.search_symbols` against a real local HTTP stub server
  (not mocked) -- including the connection-failure path, which needed an
  explicit `on_error` handler for `plenary.curl` since its default
  behavior raises an error from inside an async callback that a `pcall`
  around the call site can't actually catch.
- `stexmode.lsp.ensure_client` against a stubbed LSP client object,
  confirming the `flams/serverURL` handler gets attached even to a
  client this module didn't start itself (e.g. one `nvim-lspconfig`
  already created), not just ones it launches standalone.
- The full Telescope picker construction end-to-end against the same
  real HTTP stub: `finder.fn`/`finder.entry_maker`, called exactly the
  way `telescope.finders.DynamicFinder:_find` calls them internally
  (confirmed by reading that method's source), through to
  `_on_select` actually inserting the right `\usemodule`.
