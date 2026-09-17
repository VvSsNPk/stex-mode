--- Connection management for the flams language server.
---
--- Neovim's built-in LSP client (`vim.lsp`) is the Neovim analog of
--- eglot -- a thin wrapper over the LSP protocol -- so this mirrors
--- stex-mode.el's own connection handling: reuse any already-running
--- `flams` client if one exists (e.g. started by nvim-lspconfig for
--- the current .tex buffer already), otherwise start a standalone one
--- in `config.mathhub_root` so MathHub search works with no .tex
--- buffer open at all, same as stex-mode.el's
--- `stex--ensure-mathhub-server`.  Either way, `base_url` isn't known
--- until flams reports it via its custom `flams/serverURL`
--- notification (there's no synchronous way to get it, same
--- constraint as the Emacs side), so `ensure_client` blocks briefly
--- (`vim.wait`) for that to arrive.

local M = {}

--- The reporting client's HTTP base URL, once known.  nil until the
--- `flams/serverURL` notification handler has fired at least once.
M.base_url = nil

--- Return a live `flams`-named LSP client already attached to some
--- buffer, or nil if none is running.
function M.find_live_client()
  local clients = vim.lsp.get_clients({ name = "flams" })
  for _, client in ipairs(clients) do
    if not client:is_stopped() then
      return client
    end
  end
  return nil
end

local function on_server_url(_, result)
  if result and result.url then
    M.base_url = result.url
  end
end

--- Make sure CLIENT's `flams/serverURL` notifications are routed to
--- `on_server_url`.  Needed not just for a client we start ourselves
--- (`start_client` below) but also for one `find_live_client` merely
--- *found* -- e.g. started by nvim-lspconfig for a .tex buffer rather
--- than by this plugin -- since our handler was never registered on
--- that one.  Overwrites any existing handler for this one method on
--- CLIENT; a deliberate tradeoff, not expected to collide with
--- anything in practice.
local function attach_handler(client)
  client.handlers["flams/serverURL"] = on_server_url
  return client
end

--- Start a standalone flams connection in `config.mathhub_root` (or
--- the cwd, if unset).  Does not wait for it to come up -- see
--- `ensure_client`, which polls `M.base_url` afterward.
local function start_client()
  local config = require("stexmode").config
  local client_id = vim.lsp.start({
    name = "flams",
    cmd = config.cmd,
    root_dir = config.mathhub_root or vim.fn.getcwd(),
    handlers = { ["flams/serverURL"] = on_server_url },
  })
  if not client_id then
    error("stexmode: failed to start the flams LSP client (check `cmd`/`mathhub_root`)")
  end
  return vim.lsp.get_client_by_id(client_id)
end

--- Return a live flams client, starting a standalone one if nothing
--- is connected anywhere, and block (via `vim.wait`) until its HTTP
--- URL is known.  Raises a Lua error (not a return value) on
--- failure/timeout, so callers should `pcall` this.
function M.ensure_client()
  local config = require("stexmode").config
  local client = attach_handler(M.find_live_client() or start_client())
  local timeout_ms = (config.connect_timeout or 20) * 1000
  local ok = vim.wait(timeout_ms, function()
    return M.base_url ~= nil
  end, 100)
  if not ok then
    error("stexmode: timed out waiting for flams to report its HTTP URL")
  end
  return client
end

return M
