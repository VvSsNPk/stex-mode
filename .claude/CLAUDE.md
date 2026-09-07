# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repo holds two related pieces:

- **Root (`stex-mode.el`, `eldev`)** — an Emacs package that connects `latex-mode`/`LaTeX-mode` buffers to the `flams` LSP server via built-in `eglot`, mirroring a subset of the `vscode/` extension's command set (build/export, not the MathHub browser or previews — see the header Commentary in `stex-mode.el` for exact scope). `eldev` is just the vendored [Eldev](https://github.com/emacs-eldev/eldev) bootstrap shell script — there is no `Eldev` project file yet, so `./eldev test`/`./eldev lint` won't do anything meaningful until one is added. For now, verify with plain Emacs batch mode: `emacs -Q --batch -L . -f batch-byte-compile stex-mode.el` and `emacs -Q --batch -l checkdoc --eval '(checkdoc-file "stex-mode.el")'`.
- **`vscode/`** — a working VS Code/VSCodium extension ("FLAMS", package name `flams`) for the FLAMS system and sTeX. This is the fuller-featured reference implementation (MathHub tree, HTML/quiz previews, call hierarchy, setup/installer wizard) that `stex-mode.el` is catching up to.

There is no root README and no git repository initialized.

## `stex-mode.el` — the Emacs package

Single-file package, no build step. Loads via `(require 'stex-mode)` /
`(load-file "stex-mode.el")`.

- `stex-mode` is a **buffer-local minor mode**, not something this package
  turns on globally — the user opts in per major-mode hook (e.g.
  `(add-hook 'LaTeX-mode-hook #'stex-mode)`). On enable it buffer-locally
  prepends a `flams` entry to `eglot-server-programs` (via `setq-local`) so
  it doesn't clobber other LaTeX buffers' server config (e.g. digestif/texlab
  configured elsewhere), then calls `(eglot-ensure)`. On disable it restores
  `eglot-server-programs` via `kill-local-variable`.
- `stex--check-setup` (ported from the vscode extension's `versions.ts`)
  verifies the `flams` executable and sTeX installation are present and meet
  `stex--required-flams-version`/`stex--required-stex-version` before
  connecting, signaling `user-error` with a specific diagnosis otherwise.
  Unlike the vscode extension's `setup.ts`, there is **no interactive
  download/install wizard** — the user is pointed at
  `M-x customize-group RET stex RET` instead.
- Build/export commands (`stex-build-file`, `stex-build-all`,
  `stex-export-tex`, `stex-export-html`) talk to the connected `flams`
  server directly over its custom LSP methods (`flams/buildOne`,
  `flams/buildAll`, `flams/standaloneExport`, `flams/htmlExport`) via
  `jsonrpc-async-request`/`jsonrpc-notify` on `(eglot-current-server)` — same
  wire protocol as `vscode/src/ts/commands.ts`, just called directly instead
  of through a bespoke context object (eglot's server registry already
  provides that bookkeeping).
- The eglot connection uses a dedicated `stex-eglot-server` class (subclass
  of `eglot-lsp-server`, selected by returning `(list 'stex-eglot-server
  exe ...)` from the `eglot-server-programs` contact function) instead of
  the generic one, purely so there's a slot (`stex-eglot-server-http-url`)
  to stash the HTTP base URL the server reports over the `flams/serverURL`
  notification. MathHub browsing is the only thing that needs it — build/
  export commands are pure LSP and don't touch HTTP at all.
- MathHub browsing (`stex-mathhub-open-file`, `stex-mathhub-insert-usemodule`)
  is **local archives only** — no remote-server merge/install (`flams.ts`'s
  dual local+remote tree in `mathhub.ts`) and no fuzzy module search (that's
  flams's own web UI loaded in a webview iframe in the vscode extension, not
  a documented REST endpoint — nothing to port without embedding a browser).
  It talks to three plain HTTP `POST` JSON endpoints on the server's HTTP
  URL (`api/settings`, `api/backend/group_entries`,
  `api/backend/archive_entries`, all mirrored from `flams.ts`/`mathhub.ts`)
  via a small synchronous client (`stex--http-post`, built on `url.el` +
  `json-parse-string`, no external dependency). Navigation is a
  `completing-read`-based drill-down (`stex--drill-down`) rather than a
  tree-sidebar widget — deliberately simpler than `MathHubTreeProvider`,
  works with whatever completion UI is already configured (vertico, etc.).
  `\usemodule` insertion (`stex--insert-usemodule`) is a direct port of
  `insertUsemodule` in `vscode/src/ts/utils.ts`, including its exact
  insertion-point rule (after `\begin{document}`, skipping blank/existing
  `\usemodule`/`\importmodule` lines; falls back to the very top of the
  buffer if there's no `\begin{document}` at all).
- Not implemented: remote MathHub browsing/install, HTML/quiz preview
  panes, the fuzzy module-search UI, call-hierarchy view,
  `vscode://flams/open`-equivalent URI handling. These map to the remote-
  server half of `mathhub.ts`, the webview code in `commands.ts`, and
  `callgraph.ts` in `vscode/` — none of it is ported yet.

## `vscode/` — the FLAMS extension

### Commands

Run from inside `vscode/`:

```
npm install            # install dependencies (first time / after package.json changes)
npm run build           # webpack bundle -> dist/extension.js (dev)
npm run watch           # webpack in watch mode
npm run package          # production build (minified, hidden source map) — used by vscode:prepublish
npm run lint             # eslint src
npm run compile-tests    # tsc -p . --outDir out (compiles src + test sources for @vscode/test-electron)
npm test                 # vscode-test — runs the extension in a real VS Code instance; runs pretest (compile-tests, compile, lint) first
```

There is no dedicated "run a single test" script; `@vscode/test-electron` drives whatever tests are compiled into `out/`. Check `.vscode/launch.json` for the debug configuration if you need to launch the extension in a dev host instead.

### Architecture

The extension talks to two external, separately-built binaries that are not part of this repo:
- **`flams`** — the language server binary (path configured via `flams.flams_path`, or auto-installed by the setup flow).
- **`stex`** — required alongside it; both have minimum version requirements enforced by `versions.ts` (`REQUIRED_FLAMS`, `REQUIRED_STEX`).

Flow, entry point `src/extension.ts`:

1. `activate()` registers a URI handler (`vscode://flams/open?a=<archive>&rp=<relative-path>`, resolved against configured MathHub directories) and calls `local()`.
2. `local()` builds a `FLAMSPreContext` (holds `vscode.ExtensionContext`, an output channel, and a `Versions` checker) and registers the pre-launch commands.
3. If `Versions.isValid()` passes, `launch_local()` starts the `flams` binary in LSP mode (`--lsp [-c <settings.toml>]`) via `vscode-languageclient` and wires up a `FLAMSServer` (HTTP client, `ts/flams.ts`) once the server reports its URL over the `flams/serverURL` notification. Otherwise `setup()` (`ts/setup.ts`) drives an interactive download/install flow for the missing/outdated binaries (`ts/utils.ts` has the download/unzip helpers).
4. Once the server URL is known, a `FLAMSContext` (superset of `FLAMSPreContext`, requires `client`/`server` to be non-null) replaces the pre-context as the global singleton (`getContext()` / `awaitContext()`), and `register_server_commands()` registers the commands/views that need a live server (build, export, MathHub tree, call hierarchy).

There's a dormant `remote()` path (commented out in `extension.ts`) for connecting to a remote FLAMS server over WebSocket instead of spawning a local process — not currently wired up.

Module responsibilities under `src/ts/`:
- `flams.ts` — thin HTTP client (`FLAMSServer`) and shared API types (mirrors types from the `@flexiformal/ftml-backend` package).
- `versions.ts` — locates/validates the `flams`/`stex` binaries and their versions.
- `setup.ts` — first-run UX for downloading/installing `flams`/`stex` when missing or outdated.
- `mathhub.ts` — MathHub archive settings/tree view (`MathHubTreeProvider`) shown in the sidebar.
- `commands.ts` — command IDs (`Commands` enum), settings keys (`Settings` enum), and registration of both pre-server (`register_commands`) and post-server (`register_server_commands`) VS Code commands.
- `callgraph.ts` — tree providers for call-hierarchy and document-symbol views.
- `utils.ts` — misc helpers: shell exec, file download/unzip, inserting `\usemodule` into a document.

Two context classes exist because most commands need a live LSP client/server, but a handful (the setup/install flow) must work before one exists — `FLAMSPreContext` vs. `FLAMSContext` encodes that split at the type level.

Build pipeline: TypeScript in `src/` → webpack (`webpack.config.js`, entry `src/extension.ts`) → single bundle `dist/extension.js` (the `main` in `package.json`). `vscode` itself is external (provided by the host, not bundled). There's a leftover Rust/WASM path (`src/lib.rs.ignore`, `src/vscode.rs.ignore`, `Cargo.toml.ignore`, the `ignore-this` npm script) that is disabled (`.ignore` extensions) — not part of the current build.

The extension declares a hard dependency on `james-yu.latex-workshop` (`extensionDependencies`) and activates on any workspace containing `.tex` files or via its custom URI scheme.
