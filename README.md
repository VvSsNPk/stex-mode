# stex-mode

An Emacs minor mode that connects `latex-mode`/`LaTeX-mode` buffers to the
[FLAMS](https://github.com/FlexiFormal/FLAMS) language server (`flams`) via
Emacs's built-in `eglot`, for working with [sTeX](https://github.com/KWARC/FLAMS)
content. It's an Emacs-native counterpart to FLAMS's own
[VS Code/VSCodium extension](vscode/) (vendored in this repo under `vscode/`
as a reference implementation), covering the LSP-driven parts of that
extension's command set: build/export, MathHub archive browsing, HTML
preview, and call hierarchy.

## What it does

`stex-mode` is a **buffer-local minor mode**, not something this package
turns on globally. You opt in per major-mode hook:

```elisp
(add-to-list 'load-path "/path/to/stexmode")
(require 'stex-mode)
(add-hook 'LaTeX-mode-hook #'stex-mode)
```

Enabling it in a buffer:

1. Runs a setup check (`flams` executable found and new enough, LaTeX +
   sTeX installed and new enough) -- see [Getting flams and sTeX](#getting-flams-and-stex)
   below if this fails.
2. Buffer-locally prepends a `flams` entry to `eglot-server-programs` (it
   does **not** touch the global default, so it won't affect other LaTeX
   buffers using a regular language server like digestif or texlab) and
   starts `flams --lsp` for that buffer via `eglot-ensure`.
3. Makes the commands below available, all under the `C-c C-x` prefix (see
   `stex-mode-map`; chosen because it isn't already claimed by AUCTeX or
   `preview.el`'s default keymaps).

| Key         | Command                          | What it does |
|-------------|-----------------------------------|--------------|
| `C-c C-x c` | `stex-connect`                    | (Re)verify setup and connect |
| `C-c C-x f` | `stex-build-file`                 | Build the current file |
| `C-c C-x F` | `stex-build-all`                  | Build recursively from the current file |
| `C-c C-x d` | `stex-build-dashboard`            | Open the build dashboard (queue, log) in a browser |
| `C-c C-x e` | `stex-export-tex`                 | Export a standalone `.tex` package |
| `C-c C-x E` | `stex-export-html`                | Export standalone HTML |
| `C-c C-x p` | `stex-preview-browser`            | Build an HTML preview and open it in a browser |
| `C-c C-x o` | `stex-mathhub-open-file`          | Drill down local MathHub archives, open a file |
| `C-c C-x u` | `stex-mathhub-insert-usemodule`   | Drill down local MathHub archives, insert `\usemodule` |
| `C-c C-x s` | `stex-mathhub-search-symbols`     | Fuzzy-search all indexed symbols, insert `\usemodule` |
| `C-c C-x S` | `stex-mathhub-search`             | Fuzzy-search indexed content by category, open the file |
| `C-c C-x t` | `stex-mathhub-tree`               | Whole local MathHub as a persistent tree (side window) |
| `C-c C-x a` | `stex-mathhub-new-archive`        | Create a new MathHub archive |
| `C-c C-x U` | `stex-mathhub-update`             | `git pull` local archives (see scopes below) |
| `C-c C-x h` | `stex-show-call-hierarchy`        | Call hierarchy for the symbol at point (side window) |
| `C-c C-x i` | `imenu`                           | Jump to a symbol in the current file |

The VS Code extension shows build progress in a webview panel, which
turns out to just be an `<iframe>` onto a page `flams` serves directly
over plain HTTP (`/dashboard/queue`) -- nothing VS Code-specific about
it. `stex-build-file`/`stex-build-all` open that same page in your
browser right after queuing a build (set `stex-build-auto-dashboard` to
nil to turn that off), and `stex-build-dashboard` opens it on demand.
No in-Emacs webview rendering -- same tradeoff as `stex-preview-browser`
below, and it only needs the server's HTTP URL, which it reads
opportunistically without ever blocking a build on it.

The last two aren't really `stex-mode`-specific: call hierarchy and
document symbols are `eglot`'s own generic LSP features (`imenu` is wired
up automatically for any eglot-managed buffer), available for free as long
as `flams` advertises the corresponding LSP capabilities.
`stex-show-call-hierarchy` is a thin wrapper that additionally puts the
results in a configurable side window (`stex-call-hierarchy-side`,
`stex-call-hierarchy-width`) instead of wherever `display-buffer` would
otherwise put them.

MathHub browsing is **local archives only** -- it asks the connected
`flams` server which MathHub directories it's configured with (no local
configuration needed on the Emacs side). `stex-mathhub-open-file` and
`stex-mathhub-insert-usemodule` drill down through archive groups,
archives, directories and files one `completing-read` prompt at a time;
`stex-mathhub-tree` instead shows the whole thing at once, as one
persistent, `dired`-like `tree-widget`-based tree in a side window
(`stex-mathhub-tree-side`/`stex-mathhub-tree-width`, default: right, 25%
of frame width), reconfigurable in place instead of needing separate
commands:

| Key | Command | What it does |
|-----|---------|---------------|
| `n` | `stex-mathhub-tree-narrow` | Narrow the tree to the group/archive at point |
| `^` | `stex-mathhub-tree-up` | Undo the last narrow |
| `o` | `stex-mathhub-tree-open` | Open the file on the current line |
| `u` | `stex-mathhub-tree-insert-usemodule` | `\usemodule` for it, into whatever window you were last in |
| `a` | `stex-mathhub-new-archive` | Create a new archive (see below) |
| `U` | `stex-mathhub-update` | `git pull` local archives (see below) |
| `p` | `stex-mathhub-tree-update-at-point` | `git pull` just the archive/group on the current line |
| `g` | `revert-buffer` | Full reset to the whole MathHub |

`stex-mathhub-new-archive` creates a new MathHub archive -- prompts for an
archive id (e.g. `My/Archive/Name`) and a URL base, then sends
`flams/newArchive` (a direct port of the "New Math Archive" flow in
`vscode/src/ts/commands.ts`). The tree, if open, refreshes itself
automatically once `flams` confirms the change (`flams/updateMathHub`).

`stex-mathhub-update` runs `git pull --ff-only` in every git repository
under some scope, one at a time, asynchronously (Emacs stays responsive),
with progress and a final summary in `*sTeX MathHub Update*`. Scope
depends on a prefix argument: none = the whole MathHub, one `C-u` = a
single archive you pick (`stex-mathhub-update-archive`, also directly
`M-x`-able), two `C-u C-u` = a whole group you pick
(`stex-mathhub-update-group`, likewise `M-x`-able) -- mirrors how
`stex-show-call-hierarchy` already uses a prefix argument to pick a
direction. Inside the tree, `stex-mathhub-tree-update-at-point` pulls
whatever archive/group is on the current line without re-prompting for
it. There's no `flams`/vscode equivalent to any of this -- checked the
vscode extension's full list of custom LSP methods and REST endpoints,
none of them do it (`flams/install` is for archives you don't have *yet*,
not updating ones you do). Archives that would need a password or SSH
passphrase to pull are detected (git/ssh are forced to fail immediately
instead of prompting, so nothing ever hangs) and reported as skipped
rather than failing the whole run.

None of the MathHub commands need a `.tex` file open at all -- if nothing
is already connected anywhere (in any buffer, this one or not), they
launch a standalone `flams` connection against `stex-mathhub-root` and
wait for it (`stex-mathhub-connect-timeout`). There's no remote-archive
browsing/install (installing an *existing* remote archive, that is --
distinct from creating a brand new one, which is local-only and needs no
remote server).

`stex-mathhub-search-symbols` is a real, incremental fuzzy search over
every symbol FLAMS has indexed across your whole MathHub -- not just
local drill-down, and not just this buffer's own declarations (that's
the local completion above). The VS Code extension shows this as a
webview iframe onto FLAMS's own search page; that page turns out to be
a thin frontend over a plain HTTP endpoint (`POST api/search_symbols`),
so `stex-mode` queries it directly instead, feeding the results into a
real Emacs `completing-read` (via `completion-table-dynamic`, so it
re-queries on every keystroke) rather than embedding a browser. Pick a
result and it inserts a `\usemodule` for that symbol's module, same
end result as the VS Code webview's search-then-click flow.

`stex-mathhub-search` is the same idea over a richer endpoint,
`POST api/search`, which also indexes whole documents and individual
paragraphs/definitions/examples/assertions/problems, not just symbols --
mirroring the category checkboxes (Documents, Paragraphs, Definitions,
Examples, Assertions, Problems) in VS Code's own search webview. Prompts
first for zero or more categories to restrict to (empty = everything),
then searches incrementally the same way `stex-mathhub-search-symbols`
does; picking a result opens its file (there's no `\usemodule` target
here -- a paragraph-level result is a spot *within* a document, not a
module to import).

## Inserting sTeX environments

If [AUCTeX](https://www.gnu.org/software/auctex/) is loaded, enabling
`stex-mode` also teaches its `LaTeX-environment` command (`C-c C-e` by
default) about sTeX's own environments, the same way loading a LaTeX
package's style file would. `C-c C-e smodule RET` and the like now prompt
for that environment's actual options (`title=`, `style=`, `id=`, ...)
instead of leaving you to type `[key=val,...]{...}` out by hand:

| Environment | Prompts for |
|-------------|--------------|
| `smodule` | `title`, `style`, `id`, `ns`, `lang`, `sig` options, then the module name |
| `sfragment` | `id`, `short` options, then the section title |
| `sparagraph`, `sdefinition`, `sassertion`, `sexample` | `for`, `style`, `title`, `id`, `name`, `macro` options (`style` completes to `theorem`/`lemma`/`corollary`/`axiom`/`definition`/`example`/`counterexample`) |
| `mathstructure` | The structure name, then `name`, `this` options |
| `sproblem`, `subproblem` | `id`, `pts`, `min`, `title` options |
| `solution` | `id`, `title`, `style`, `testspace`, `answerclass` options |

`sproof`, `subproof`, `blindfragment`, `hint`, `exnote` and `gnote` are
also added to the completion list, without special option prompting.
Nothing here rebinds `C-c C-e` or adds a new command -- it only extends
the list AUCTeX's own command already completes over, for the current
buffer (see `stex--register-environments`). Argument lists follow the
STEX manual's chapters on document features, modules/symbols and
statements.

## Inserting sTeX macros

The same idea applies to AUCTeX's `TeX-insert-macro` command (`C-c C-m`
by default): with AUCTeX loaded, enabling `stex-mode` teaches it sTeX's
symbol-declaration, notation, variable and cross-reference macros too
(see `stex--register-macros`):

| Macro | Prompts for |
|-------|--------------|
| `\symdecl`, `\symdecl*` | The macro name, then `name`, `args`, `type`, `def`, `return`, `assoc`, `reorder`, `role` options |
| `\textsymdecl` | The macro name, then those same options minus `args` (a `\textsymdecl` symbol always has arity 0), then the output code |
| `\symdef` | The macro name, then `\symdecl`'s and `\notation`'s options combined, then the notation |
| `\notation`, `\notation*` | The symbol, then `prec`, `op`, `variant` options, then the notation code |
| `\symref`, `\sr` | `pre`, `post` options, then the symbol, then the text |
| `\symname`, `\sn` | `pre`, `post` options, then the symbol |
| `\symuse` | Just the symbol |
| `\definiendum` | `gf`, `root` options, then the symbol, then the text |
| `\definame`, `\Definame` | `pre`, `post`, `gf`, `root` options, then the symbol |
| `\Symname` | `pre`, `post` options, then the symbol (capitalizing variant of `\symname`) |
| `\sns`, `\Sns` | Just the symbol -- these hardcode `post=s`, so no options to prompt for |
| `\defnotation` | Just the notation (applies `\definiendum`-style highlighting to it, in math mode) |
| `\definiens` | The symbol (optional -- only needed with several symbols in scope), then the text |
| `\vardef` | The macro name, then `\symdef`'s options plus `bind`, then the notation |
| `\varnotation` | The variable, then `prec`, `op`, `variant` options, then the notation |
| `\varseq` | The macro name, then `\vardef`'s options, then the range, then the notation |
| `\svar` | An optional display name, then the text |
| `\varbind` | A comma-separated list of variables |
| `\varref` | `pre`, `post` options, then the variable, then the text |
| `\varname`, `\Varname` | `pre`, `post` options, then the variable |
| `\premise` | An optional variable name, then the text |
| `\conclusion` | An optional symbol, then the text |
| `\comp`, `\maincomp` | Just the notation component to highlight |
| `\setnotation` | The symbol, then the notation id to make default |
| `\arg`, `\arg*` | An optional argument number, then the text |
| `\srefsym` | The symbol, then the text |
| `\srefsymuri` | The symbol's full URI, then the text |
| `\sref` | `archive`/`file`/`fallback`/`pre`/`post` options, then the label, then `archive`/`file`/`title` options |
| `\extref` | Same as `\sref`, but the second options group is mandatory (braces, not brackets) |
| `\srefsetin` | An optional archive, then the file, then the title |
| `\sreflabel` | Just the label |
| `\inputref`, `\mhinput` | An optional archive, then the file |
| `\requiremodule` | Just the module |

The `\symref`/`\definiendum`/`\definame` option sets were checked against
their actual `expl3` definitions rather than the STEX manual's simplified
tutorial prose, which undersells what a couple of them accept (`\symref`
turns out to take the same `pre=`/`post=` options as `\symname`, for
instance). As with environments, this only extends AUCTeX's existing
completion list for the current buffer -- no new command, no rebinding.

`stex-mode` also protects `\notation`/`\notation*`'s and `\symdef`'s
final argument (the actual notation code) and `\textsymdecl`'s output
argument from `M-q`/auto-fill reflow -- these hold presentation code,
not prose, so line-wrapping them mid-argument would be actively
unwelcome even though it's harmless to LaTeX itself. This works the
same way AUCTeX already protects `\verb|...|` (via `fill-nobreak-predicate`,
a standard Emacs Lisp fill hook), but without treating the argument as
verbatim text the way `LaTeX-verbatim-macros-with-braces` would -- it's
ordinary LaTeX in there (nested macros like `\comp{...}` are still
recognized as such, still font-locked normally), only line-breaking is
suppressed. Text outside these arguments (including `\symdecl`, which
has no such argument at all, and `\definiendum`/`\definame`, whose text
argument *is* prose) fills exactly as before.

## Symbol-name completion

`flams`'s own LSP `completion` request is a permanent stub as of this
writing (confirmed by reading FLAMS's server source directly), so eglot
has nothing to offer while typing a symbol name. `stex-mode` fills part
of that gap locally: while point is inside the symbol argument of
`\symref`/`\sr`/`\symname`/`\sn`/`\symuse`/`\definiendum`/`\definame`,
it offers completion (via the standard `completion-at-point-functions`
mechanism -- so it works with whatever completion UI you already use,
`corfu`/`company`/the built-in one) drawn from:

- every `\symdecl`/`\symdecl*`/`\textsymdecl`/`\symdef` declaration in
  the current buffer;
- the same, in any file the buffer references via a plain
  `\usemodule{X}`/`\importmodule{X}` (no `[archive]` override) that
  resolves to a sibling `X.tex`/`X.<lang>.tex` file -- resolving a
  cross-archive `\usemodule[archive]{X}` would need a live MathHub
  connection, which a completion function must never block on, so
  those are skipped.

This is a local, best-effort stand-in, not real semantic completion:
it doesn't follow a used module's own imports transitively, and it
doesn't honor an explicit `name=` override in a `\symdecl`'s options
(both deliberately out of scope). See `stex--register-macros` and
`stex--symbol-completion-at-point`.

A non-starred `\symdecl`/`\textsymdecl`/`\symdef` doesn't just declare a
symbol -- it also generates a same-named semantic macro usable directly
in the document (e.g. `\symdef{mult}[...]{...}` gives you a real `\mult`
macro to write, per the STEX manual's "Semantic Macros" section). AUCTeX's
own macro completion has no way to know that, since it only tracks macros
declared the ordinary way (`\newcommand`/`\def`). So `stex-mode` also
completes `\NAME` for every such declaration, anywhere in the buffer --
same source data as above, just offered as a macro invocation instead of
a bare symbol-argument reference, and (correctly) excluding `\symdecl*`
declarations, which explicitly don't generate a macro. See
`stex--macro-name-completion-at-point`.

## Folding notation code

`\notation`/`\notation*`/`\symdef`/`\textsymdecl` definitions can run
long, and once written, the interesting part to see while editing
surrounding text is usually the notation itself, not the whole
`\notation{sym}[prec=...]{...}` wrapper. If AUCTeX's own `TeX-fold-mode`
is available, `stex-mode` teaches it to fold these down to just their
notation/output argument (whitespace-collapsed onto one line, truncated
with an ellipsis past `stex-fold-notation-max-length` characters)
instead of AUCTeX's generic `[m]` placeholder for an unrecognized macro
-- the same folding mechanism AUCTeX already uses for e.g. `\section`/
`\emph` (`C-c C-o C-b` to fold the whole buffer, `C-c C-o C-o` to
unfold at point, etc. -- see AUCTeX's own manual for the full `TeX-fold`
keymap). Note AUCTeX's own caveat applies here too: if `TeX-fold-mode`
was already on in a buffer before `stex-mode` enabled, it needs to be
toggled off and back on for this to take effect, since
`TeX-fold-macro-spec-list` changes aren't picked up live.

## Prettified macros

AUCTeX already sets up `prettify-symbols-alist` for every `LaTeX-mode`
buffer with the standard ~600-entry table of LaTeX math symbols (`\alpha`
-> α, `\rightarrow` -> →, ...) that plain Emacs's own `tex-mode.el` ships
-- it's just off by default (`prettify-symbols-mode` is a plain toggle).
None of that table covers sTeX's own macros, though, so enabling
`stex-mode` also turns on `prettify-symbols-mode` and extends that table
with glyphs for `\importmodule`, `\symdecl`, `\symdef`, `\notation`,
`\symref`, `\definiendum` and the rest of the macros `stex-mode` teaches
`C-c C-m` about (see `stex-prettify-symbols-alist`) -- the buffer text is
untouched, only how it's *displayed* changes, so nothing about editing,
searching, or what gets sent to `flams` is affected. Set
`stex-prettify-symbols` to nil to skip this entirely (leaves
`prettify-symbols-mode`/`prettify-symbols-alist` alone), or customize
`stex-prettify-symbols-alist` to change/add glyphs -- the choices there
are this package's own curated picks, not something FLAMS or the VS Code
extension define.

## Live-reloading previews

The VS Code extension refreshes an already-open preview webview in place
via a trick specific to VS Code's own webview API (see the build-dashboard
section above for the same idea applied there) -- and FLAMS's own preview
page has no self-refresh wiring of its own to lean on instead (checked its
source directly: no websocket/SSE tied to rebuilds). So instead,
`stex-mode` runs its own tiny local relay: by default
(`stex-preview-live-reload`, on unless you turn it off), `stex-preview-browser`
and the automatic `flams/htmlResult` handling open a small wrapper page
served by a `127.0.0.1`-only server `stex-mode` starts on demand, which
iframes the real preview and holds open a Server-Sent-Events connection
back to that relay. Whenever `flams` rebuilds the same document again, the
relay pushes a reload event down that connection and the wrapper force-
reloads its iframe -- so a preview tab already open in your browser updates
itself, the same live-updating experience VS Code's embedded webview gets,
without Emacs needing to control the browser at all (no `xwidgets`
dependency, works with whatever browser `browse-url` opens).

Set `stex-preview-live-reload` to nil to open FLAMS's preview URL directly
instead -- no live reload, and no local server ever starts. See
`stex--preview-relay-ensure` and the rest of that section in `stex-mode.el`
for how the relay itself works (a hand-rolled two-route HTTP server, since
pulling in a real web server package for `/preview` and `/events` would be
disproportionate).

## Configuration

`M-x customize-group RET stex RET`, or `setq`/`setopt` directly:

- `stex-flams-executable` -- path to `flams`; defaults to whatever
  `executable-find` finds on `PATH`.
- `stex-settings-toml` -- path to a FLAMS `settings.toml`, passed as
  `-c PATH` to `flams --lsp`.
- `stex-call-hierarchy-side` / `stex-call-hierarchy-width` -- side-window
  placement for `stex-show-call-hierarchy` (default: left, 30% of frame
  width).
- `stex-mathhub-tree-side` / `stex-mathhub-tree-width` -- side-window
  placement for `stex-mathhub-tree` (default: right, 25% of frame width).
- `stex-mathhub-root` -- directory to run a standalone `flams` connection
  in for MathHub browsing with no `.tex` file open; irrelevant once
  something is already connected (default: unset -- MathHub commands
  error, telling you to set this or open a `.tex` file, if nothing's
  connected and this is unset).
- `stex-mathhub-connect-timeout` -- seconds to wait for that standalone
  connection to come up (default: 20).
- `stex-preview-auto-open` -- whether `stex-mode` should open a browser
  automatically whenever the server reports a fresh HTML build, rather
  than just messaging that one's ready (default: off, to avoid surprise
  browser tabs).
- `stex-build-auto-dashboard` -- whether `stex-build-file`/`stex-build-all`
  should open the build dashboard automatically after queuing a build
  (default: on, matching the VS Code extension's own always-on behavior
  there; unlike `stex-preview-auto-open`, this is a direct response to
  your own explicit build command, not an unsolicited server push).
- `stex-preview-live-reload` -- whether preview links route through the
  local live-reload relay (default: on) instead of opening FLAMS's
  preview URL directly (off); see [Live-reloading previews](#live-reloading-previews).
- `stex-fold-notation-max-length` -- how many characters of a folded
  `\notation`/`\symdef` argument to show before truncating with an
  ellipsis (default: 40); see [Folding notation code](#folding-notation-code).
- `stex-prettify-symbols` -- whether `stex-mode` turns on
  `prettify-symbols-mode` and extends `prettify-symbols-alist` with sTeX
  macro glyphs (default: on); see [Prettified macros](#prettified-macros).
- `stex-prettify-symbols-alist` -- the sTeX macro -> glyph table itself,
  customize to change/add entries.

## Getting flams and sTeX

`stex-mode` doesn't install or bundle either of these -- you need:

- **`flams`**, the language server binary. Get it from the
  [FLAMS releases](https://github.com/FlexiFormal/FLAMS/releases) (the
  extension's own setup code also points at `github.com/KWARC/FLAMS`,
  which appears to be an older/alias name for the same project). Point
  `stex-flams-executable` at it if it's not already on `PATH`.
- **sTeX**, the LaTeX package, installed such that `kpsewhich stex.sty`
  finds it (i.e. on your normal TeX package search path).

Current minimum versions this mode expects: `flams` >= 0.0.6, sTeX >= 4.1.0
(see `stex--required-flams-version`/`stex--required-stex-version` in
`stex-mode.el` -- these mirror the same constants in the VS Code
extension's `versions.ts`). `M-x stex-mode` or `M-x stex-connect` will tell
you specifically what's missing or outdated if the check fails.

## Requirements

- Emacs 30.1+ (for built-in `eglot`/`jsonrpc`, specifically the public
  `eglot-path-to-uri`, which isn't available before 30.1; no external
  Emacs package dependencies).
- No build step -- it's a single file, `stex-mode.el`.

Verify it loads cleanly with:

```sh
emacs -Q --batch -L . -f batch-byte-compile stex-mode.el
emacs -Q --batch -l checkdoc --eval '(checkdoc-file "stex-mode.el")'
```

## What's not implemented

Remote MathHub browsing/archive installation, the quiz preview pane, and
the interactive flams/stex download-and-install
wizard that the VS Code extension offers (you're expected to have `flams`
and sTeX installed already; `stex-mode` only checks and reports, it
doesn't fetch anything for you). See `stex-mode.el`'s Commentary header and
`.claude/CLAUDE.md` for the architecture and exactly which parts of
`vscode/` each piece maps to.

## Repository layout

- `stex-mode.el` -- the Emacs package, see above.
- `vscode/` -- FLAMS's VS Code/VSCodium extension, vendored here as the
  fuller-featured reference implementation `stex-mode.el` follows. Not an
  Emacs dependency; see `vscode/README.md`.
- `neovim/` -- a Neovim/Lua counterpart, currently just a Telescope picker
  for fuzzy MathHub symbol search (not a full port -- see `neovim/README.md`
  for what that would take and why it isn't one).

## License

`stex-mode.el` is licensed under the GNU General Public License v3.0 or
later -- see [`LICENSE`](LICENSE), the standard choice for Emacs Lisp
packages. `vscode/` carries its own license (also GPL-3.0, see
[`vscode/LICENSE`](vscode/LICENSE)) as part of the upstream FLAMS project.
