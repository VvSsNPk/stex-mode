--- Parsing for FLAMS's `SymbolUri` strings, as returned by
--- `api/search_symbols`.
---
--- A `SymbolUri` serializes as its own `Display` string, of the form
--- `<base>?a=<archive>&p=<path>&m=<module>&s=<symbol>` (`p=` absent
--- when the module's file and name coincide) -- confirmed by reading
--- the `Display` impls for `ArchiveUri`/`PathUri`/`ModuleUri`/
--- `SymbolUri` directly in FLAMS's `ftml_uris` crate (see
--- stex-mode.el's `.claude/CLAUDE.md`, "Fuzzy symbol search", for
--- where that was found).  This is a direct Lua port of
--- `stex--symbol-uri-component`/`stex--symbol-uri-usemodule-arg`/
--- `stex--symbol-uri-label` in stex-mode.el.

local M = {}

--- Extract query-component KEY (e.g. "a", "p", "m", "s") from URI.
--- Returns nil if KEY isn't present.
function M.component(uri, key)
  return uri:match("[?&]" .. key .. "=([^&]*)")
end

--- Return archive, module_path for inserting a \usemodule, given a
--- FLAMS symbol URI string.  module_path is "path?module" when URI
--- has a "p=" component (the file the module lives in differs from
--- the module's own name), or just the module name when it doesn't --
--- mirroring how \usemodule itself is written in both cases (STEX
--- manual, section 7.1).
function M.usemodule_arg(uri)
  local archive = M.component(uri, "a")
  local path = M.component(uri, "p")
  local module = M.component(uri, "m")
  local module_path = module
  if path then
    module_path = path .. "?" .. module
  end
  return archive, module_path
end

--- Human-readable label for URI, for the Telescope picker.
function M.label(uri)
  local symbol = M.component(uri, "s") or "?"
  local archive, module_path = M.usemodule_arg(uri)
  return string.format("%s  --  %s[%s]", symbol, archive or "?", module_path or "?")
end

return M
