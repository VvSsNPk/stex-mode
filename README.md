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
| `C-c C-x e` | `stex-export-tex`                 | Export a standalone `.tex` package |
| `C-c C-x E` | `stex-export-html`                | Export standalone HTML |
| `C-c C-x p` | `stex-preview-browser`            | Build an HTML preview and open it in a browser |
| `C-c C-x o` | `stex-mathhub-open-file`          | Drill down local MathHub archives, open a file |
| `C-c C-x u` | `stex-mathhub-insert-usemodule`   | Drill down local MathHub archives, insert `\usemodule` |
| `C-c C-x t` | `stex-mathhub-tree`               | Whole local MathHub as a persistent tree (side window) |
| `C-c C-x a` | `stex-mathhub-new-archive`        | Create a new MathHub archive |
| `C-c C-x U` | `stex-mathhub-update`             | `git pull` local archives (see scopes below) |
| `C-c C-x h` | `stex-show-call-hierarchy`        | Call hierarchy for the symbol at point (side window) |
| `C-c C-x i` | `imenu`                           | Jump to a symbol in the current file |

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
remote server), and no fuzzy module search (that one's FLAMS's own web UI,
not a documented REST endpoint -- nothing to reuse without embedding a
browser).

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

Remote MathHub browsing/archive installation, the fuzzy module-search UI,
the quiz preview pane, and the interactive flams/stex download-and-install
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

## License

`stex-mode.el` is licensed under the GNU General Public License v3.0 or
later -- see [`LICENSE`](LICENSE), the standard choice for Emacs Lisp
packages. `vscode/` carries its own license (also GPL-3.0, see
[`vscode/LICENSE`](vscode/LICENSE)) as part of the upstream FLAMS project.
