--- Registers this as a Telescope extension, so it's reachable as
--- `:Telescope stexmode search_symbols` and
--- `require("telescope").extensions.stexmode.search_symbols(opts)`,
--- for anyone who prefers that over the plain `:StexMathhubSearchSymbols`
--- user command (see ../../../plugin/stexmode.lua).

return require("telescope").register_extension({
  exports = {
    search_symbols = require("stexmode.telescope.search_symbols").search_symbols,
  },
})
