--- Fuzzy symbol search against a connected flams server.
---
--- `POST api/search_symbols` is a real, plain HTTP endpoint --
--- confirmed by reading FLAMS's own Rust source (a Leptos
--- `#[server(prefix = "/api", endpoint = "search_symbols")]` function
--- in `source/router/search/src/lib.rs`), not a documented REST API;
--- see stex-mode.el's `.claude/CLAUDE.md` ("Fuzzy symbol search") for
--- exactly how that was found.  Takes `query`/`num_results`, returns
--- `(score, SymbolUri, DocumentElementUri)` triples ranked by FLAMS's
--- own index across the whole MathHub -- the same endpoint
--- stex-mode.el's `stex-mathhub-search-symbols` already uses.

local curl = require("plenary.curl")
local util = require("stexmode.util")
local lsp = require("stexmode.lsp")

local M = {}

--- Query the connected flams server for QUERY, returning up to
--- NUM_RESULTS `{score, symbol_uri, doc_elem_uri}` triples (decoded
--- JSON, so 1-indexed Lua tables/arrays), or `{}` if `lsp.base_url`
--- isn't known yet or the request fails.
---
--- Synchronous: blocks briefly on a local HTTP round-trip.  Required
--- by `telescope.finders.new_dynamic`, whose `fn` must return its
--- results table directly rather than via a callback (confirmed by
--- reading telescope's own `finders.lua`: `DynamicFinder:_find` calls
--- `self.fn(prompt)` and iterates the return value immediately) --
--- same tradeoff `stex-mode.el`'s `stex--http-post` already makes for
--- the identical reason on the Emacs side.
function M.search_symbols(query, num_results)
  if not lsp.base_url then
    return {}
  end
  -- `on_error` is required here, not just a `pcall` around the call:
  -- on a connection failure, plenary.curl's `on_exit` raises `error()`
  -- from inside its own libuv callback (confirmed empirically -- it
  -- surfaces as a top-level "Error in command line" *after* this
  -- function has already returned), which escapes any `pcall` wrapped
  -- around the call itself.  With `on_error` supplied, that branch is
  -- taken instead and the call still just yields a nil response (per
  -- `curl.post`'s own source: the sync path always returns its
  -- `response` local, which `on_error`'s return value never touches),
  -- exactly like any other failure case below.
  local ok, response = pcall(curl.post, lsp.base_url .. "/api/search_symbols", {
    body = {
      query = util.url_encode(query),
      num_results = tostring(num_results),
    },
    timeout = 5000,
    on_error = function(_) end,
  })
  if not ok or not response or response.status ~= 200 then
    return {}
  end
  local decode_ok, decoded = pcall(vim.json.decode, response.body)
  if not decode_ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

return M
