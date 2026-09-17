;; Copyright (C) 2026 royaleinstein

;; Author: royaleinstein
;; Keywords: languages, tex
;; URL: https://github.com/KWARC/FLAMS
;; Package-Requires: ((emacs "30.1"))
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; stex-mode connects `latex-mode'/`LaTeX-mode' buffers to the FLAMS
;; language server (`flams --lsp') via eglot, and exposes the sTeX
;; build/export commands that the FLAMS VS Code extension provides:
;; build the current file, build it recursively, and export it as a
;; standalone .tex or .html package.
;;
;; This is a buffer-local minor mode.  It does not touch any global
;; eglot configuration, so it will not affect LaTeX buffers where you
;; use a regular LaTeX language server (digestif, texlab, ...).  Turn
;; it on where you want it, e.g.:
;;
;;   (add-hook 'LaTeX-mode-hook #'stex-mode)
;;
;; Before it can connect, you need:
;; - a `flams' executable (see `stex-flams-executable'), version at
;;   least 0.0.6;
;; - LaTeX (`kpsewhich' on PATH) with the sTeX package installed,
;;   version at least 4.1.0.
;;
;; `M-x stex-mode' will explain what is missing if the check fails.
;; Once connected, use `stex-build-file', `stex-build-all',
;; `stex-export-tex' and `stex-export-html'.  The VS Code extension
;; shows build progress in a webview panel that's really just an
;; iframe onto a page `flams' serves over plain HTTP; `stex-build-file'
;; and `stex-build-all' open that same page in your browser after
;; queuing a build (see `stex-build-auto-dashboard' to turn that off),
;; and `stex-build-dashboard' opens it on demand -- no in-Emacs webview
;; rendering, same tradeoff as `stex-preview-browser' below.
;;
;; `stex-mathhub-open-file' and `stex-mathhub-insert-usemodule' browse
;; your locally configured MathHub archives (queried live from the
;; connected `flams' server, so there is nothing to configure) and
;; either visit the chosen file or insert a \usemodule reference to it
;; at point, one `completing-read' drill-down at a time.
;; `stex-mathhub-tree' instead shows the whole local MathHub as one
;; persistent, `dired'-like tree in a side window, reconfigurable in
;; place (narrow to the archive at point and back out, open a file,
;; insert a \usemodule reference -- see its docstring for the full
;; keybinding list).  None of the MathHub commands need a `.tex' file
;; open at all: if nothing is already connected anywhere, they launch
;; a standalone `flams' connection against `stex-mathhub-root' and
;; wait for it.  `stex-mathhub-new-archive' creates a new MathHub
;; archive (a direct port of the "New Math Archive" flow in
;; vscode/src/ts/commands.ts); the tree, if open, refreshes itself
;; once flams confirms it via the flams/updateMathHub notification.
;; `stex-mathhub-update' git-pulls local archives (asynchronously, one
;; at a time), skipping -- rather than hanging or aborting the whole
;; run on -- any archive whose pull would need a password.  With no
;; prefix argument it updates everything under
;; `stex--mathhub-settings'; with a prefix argument, just one archive
;; you choose (`stex-mathhub-update-archive'); with two, a whole group
;; (`stex-mathhub-update-group').  Inside the MathHub tree,
;; `stex-mathhub-tree-update-at-point' updates whatever archive/group
;; is on the current line without re-prompting.  There is no
;; flams/vscode equivalent to any of this; it's a from-scratch port of
;; a plain git-pull script.  Only local archives are
;; browsed/created/updated in any of these -- there is no
;; remote-archive browsing or install-from-remote support.
;;
;; Call hierarchy and document symbols are eglot's own generic LSP
;; features, not FLAMS-specific -- `stex-show-call-hierarchy' (a thin
;; wrapper adding a configurable side window, see
;; `stex-call-hierarchy-side') and `M-x imenu' (wired up automatically
;; once connected) both work as long as `flams' advertises the
;; corresponding LSP capabilities.
;;
;; `stex-preview-browser' asks `flams' to build an HTML preview of the
;; current file and opens it in your default browser (no in-Emacs
;; render -- no webview/xwidgets dependency).  The server can also
;; push a preview proactively (flams/htmlResult) whenever it rebuilds
;; some document's HTML on its own schedule; by default `stex-mode'
;; just messages that a fresh preview is ready rather than popping a
;; browser tab uninvited -- see `stex-preview-auto-open' to change
;; that.  Either way, the tab stays live: by default
;; (`stex-preview-live-reload') preview links go through a small local
;; relay `stex-mode' runs, so a preview tab you already have open
;; force-reloads itself whenever `flams' rebuilds that document again
;; -- the same live-updating experience the VS Code extension gets
;; from its embedded webview, ported to a real external browser.
;;
;; See `stex-mode-map' for a `C-c C-x'-prefixed binding to every
;; command above.
;;
;; If AUCTeX is loaded, `stex-mode' also extends its `C-c C-e'
;; (`LaTeX-environment') with sTeX's own environments -- `smodule',
;; `sparagraph', `sdefinition', `sassertion', `sexample', `sfragment',
;; `mathstructure', `sproblem'/`subproblem', `solution' and a few more
;; -- prompting for each one's `key=val' options (title=, style=, id=,
;; ...) the same way `C-c C-e' already prompts for e.g. a `tabular'
;; environment's column format.  See `stex--register-environments'.
;; Likewise, its `C-c C-m' (`TeX-insert-macro') gains sTeX's symbol-
;; declaration, notation, variable and cross-reference macros --
;; `\symdecl', `\textsymdecl', `\symdef', `\notation', `\symref'/`\sr',
;; `\symname'/`\sn'/`\Symname'/`\Sn'/`\sns'/`\Sns', `\symuse',
;; `\definiendum', `\definame'/`\Definame', `\defnotation',
;; `\definiens', `\vardef', `\varnotation', `\varseq', `\svar',
;; `\varbind', `\varref', `\varname'/`\Varname', `\premise',
;; `\conclusion', `\comp', `\maincomp', `\setnotation', `\arg'/`\arg*',
;; `\srefsym', `\srefsymuri', `\sref', `\extref', `\srefsetin',
;; `\sreflabel', `\inputref', `\mhinput' and `\requiremodule' -- with
;; the same kind of `key=val' prompting where applicable.  It also
;; stops `M-q'/auto-fill from reflowing `\notation'/
;; `\symdef''s notation argument or `\textsymdecl''s output argument,
;; since those hold presentation code, not prose.  It also offers
;; completion for the symbol argument of `\symref'/`\sr'/`\symname'/
;; `\sn'/`\symuse'/`\definiendum'/`\definame', drawn from `\symdecl'-
;; style declarations found by scanning this buffer (and, best-effort,
;; any local file it `\usemodule's) -- a local stand-in for the LSP
;; completion `flams' itself doesn't yet implement.  A non-starred
;; `\symdecl'/`\textsymdecl'/`\symdef' also generates a same-named
;; semantic macro, so those same declarations additionally complete as
;; `\NAME' anywhere else in the buffer, not just inside those macros'
;; own symbol argument.  See `stex--register-macros'.  If AUCTeX's
;; `TeX-fold-mode' is available, `stex-mode' also teaches it to fold
;; `\notation'/`\notation*'/`\symdef'/`\textsymdecl' down to just their
;; notation/output argument (see `stex--register-fold'), instead of
;; AUCTeX's generic placeholder for unrecognized macros.
;;
;; Not implemented (yet): the quiz preview pane, remote MathHub
;; browsing and archive installation, and the interactive flams/stex
;; download-and-install wizard that the VS Code extension offers.
;; Install those tools yourself and point `stex-flams-executable' at
;; the binary.

;;; Code:

(require 'eglot)
(require 'jsonrpc)
(require 'cl-lib)
(require 'seq)
(require 'url)
(require 'browse-url)
(require 'button)
(require 'tree-widget)

(defgroup stex nil
  "Support for sTeX/FLAMS via eglot."
  :group 'languages
  :prefix "stex-")

(defcustom stex-flams-executable nil
  "Path to the `flams' executable.
When nil, `stex-mode' looks it up on variable `exec-path' via
`executable-find'."
  :type '(choice (const :tag "Look up on PATH" nil)
                  (file :tag "Path to flams executable"))
  :group 'stex)

(defcustom stex-settings-toml nil
  "Path to a FLAMS `settings.toml' file, or nil to use FLAMS's default.
Passed to `flams --lsp' as \"-c PATH\" when non-nil."
  :type '(choice (const :tag "Use default" nil)
                  (file :tag "Path to settings.toml"))
  :group 'stex)

(defcustom stex-call-hierarchy-side 'left
  "Which side to show `stex-show-call-hierarchy' results on.
One of `left' or `right' for a dedicated side window (like a
sidebar), or nil to fall back to eglot's normal buffer placement
\(wherever `display-buffer' would otherwise put it)."
  :type '(choice (const :tag "Left side window" left)
                  (const :tag "Right side window" right)
                  (const :tag "Default placement" nil))
  :group 'stex)

(defcustom stex-call-hierarchy-width 0.3
  "Width of the `stex-show-call-hierarchy' side window.
A float between 0 and 1 is a fraction of the frame width; an integer
is a number of columns.  Only used when `stex-call-hierarchy-side' is
non-nil."
  :type '(choice (float :tag "Fraction of frame width")
                  (integer :tag "Columns"))
  :group 'stex)

(defcustom stex-mathhub-tree-side 'right
  "Which side to show `stex-mathhub-tree' results on.
One of `left' or `right' for a dedicated side window (like a
sidebar), or nil to fall back to Emacs's normal buffer placement
\(wherever `display-buffer' would otherwise put it)."
  :type '(choice (const :tag "Left side window" left)
                  (const :tag "Right side window" right)
                  (const :tag "Default placement" nil))
  :group 'stex)

(defcustom stex-mathhub-tree-width 0.25
  "Width of the `stex-mathhub-tree' side window.
A float between 0 and 1 is a fraction of the frame width; an integer
is a number of columns.  Only used when `stex-mathhub-tree-side' is
non-nil."
  :type '(choice (float :tag "Fraction of frame width")
                  (integer :tag "Columns"))
  :group 'stex)

(defcustom stex-mathhub-root nil
  "Directory to run a standalone `flams' connection in.
MathHub browsing commands (`stex-mathhub-tree' etc.) need a live
`flams' connection.  If one already exists (from any `stex-mode'
buffer, anywhere), it's reused; only when none exists at all does
this matter -- it's the directory `flams' runs in so you can browse
MathHub without ever opening a `.tex' file.  Set it to your MathHub
root, or any directory `flams' is happy to run in."
  :type '(choice (const :tag "Not configured" nil) directory)
  :group 'stex)

(defcustom stex-mathhub-connect-timeout 20
  "Seconds to wait for a standalone MathHub connection to come up.
Only applies to `stex-mathhub-root'-based connections (see
`stex-mathhub-tree' etc.) -- reusing an already-connected `stex-mode'
buffer's server involves no waiting."
  :type 'integer
  :group 'stex)

(defcustom stex-preview-auto-open nil
  "Whether to open a browser automatically when an HTML preview is ready.
The server sends a flams/htmlResult notification whenever it has
\(re)built HTML output for some document, on its own schedule -- not
necessarily the file in the buffer you're looking at.  When nil (the
default), `stex-mode' just messages that a preview is ready; run
`stex-preview-browser' yourself to view it.  When non-nil, every such
notification opens a browser tab, which can be surprising if it
fires more often than you'd expect a browser popup."
  :type 'boolean
  :group 'stex)

(defcustom stex-preview-live-reload t
  "Whether preview links route through a local live-reload relay.
When non-nil (the default), `stex-preview-browser' and the automatic
`flams/htmlResult' handling open a small wrapper page served by a
`127.0.0.1'-only relay `stex-mode' starts on demand (see
`stex--preview-relay-ensure'), instead of FLAMS's preview URL
directly.  The wrapper iframes the real content and force-reloads it
whenever FLAMS rebuilds that same document, so a preview tab already
open in your browser updates itself without a manual refresh -- the
same trick the VS Code extension's embedded webview uses for itself,
ported to a real external browser since Emacs has no webview of its
own to lean on (`M-x xwidget-webkit-browse-url' isn't compiled into
most Emacs builds).  Set to nil to open FLAMS's URL directly instead
-- no live reload, and no local server ever starts."
  :type 'boolean
  :group 'stex)

(defcustom stex-build-auto-dashboard t
  "Whether `stex-build-file'/`stex-build-all' open the build dashboard.
FLAMS serves a live build-queue page over HTTP -- the same one the VS
Code extension embeds in a webview panel right after a build request.
When non-nil (the default, matching the VS Code extension's own
always-on behavior there), a successful build request opens that page
in your browser, same as calling `stex-build-dashboard' yourself.  Set
to nil to only build, without a browser tab popping up; you can still
open the dashboard on demand."
  :type 'boolean
  :group 'stex)

;; These mirror REQUIRED_FLAMS/REQUIRED_STEX in the VS Code
;; extension's src/ts/versions.ts: they encode what the LSP protocol
;; this mode speaks actually requires, not a user preference.
(defconst stex--required-flams-version '(0 0 6)
  "Minimum supported `flams' version, as (MAJOR MINOR REVISION).")

(defconst stex--required-stex-version '(4 1 0)
  "Minimum supported sTeX package version, as (MAJOR MINOR REVISION).")

;;; Version checking

(defun stex--parse-version (string)
  "Parse STRING as a \"MAJOR.MINOR.REVISION\" version.
Return a list (MAJOR MINOR REVISION), or nil if STRING doesn't match."
  (when (and string
             (string-match
              "\\([0-9]+\\)\\.\\([0-9]+\\)\\.\\([0-9]+\\)" string))
    (list (string-to-number (match-string 1 string))
          (string-to-number (match-string 2 string))
          (string-to-number (match-string 3 string)))))

(defun stex--version>= (v1 v2)
  "Return non-nil if version V1 is greater than or equal to V2.
Both are (MAJOR MINOR REVISION) lists."
  (cl-loop for a in v1
           for b in v2
           when (> a b) return t
           when (< a b) return nil
           finally return t))

(defun stex--flams-executable ()
  "Return the configured or discovered `flams' executable, or nil."
  (or stex-flams-executable (executable-find "flams")))

(defun stex--call-version (program &rest args)
  "Run PROGRAM with ARGS and return its trimmed stdout, or nil on failure."
  (when (and program (executable-find program))
    (with-temp-buffer
      (when (zerop (apply #'call-process program nil t nil args))
        (string-trim (buffer-string))))))

(defun stex--flams-version ()
  "Return the version of `stex--flams-executable' as a triple, or nil."
  (let ((exe (stex--flams-executable)))
    (when exe
      (with-temp-buffer
        (when (zerop (ignore-errors (call-process exe nil t nil "--version")))
          (goto-char (point-min))
          (when (re-search-forward
                 "flams \\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
            (stex--parse-version (match-string 1))))))))

(defun stex--has-latex-p ()
  "Return non-nil if a LaTeX toolchain (`kpsewhich') is on PATH."
  (and (executable-find "kpsewhich") t))

(defun stex--stex-sty-path ()
  "Return the path to `stex.sty' as reported by kpsewhich, or nil."
  (stex--call-version "kpsewhich" "stex.sty"))

(defun stex--stex-version ()
  "Return the installed sTeX package version as a triple, or nil."
  (let ((path (stex--stex-sty-path)))
    (when (and path (file-readable-p path))
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (when (re-search-forward
               "This~is~sTeX~version~\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (stex--parse-version (match-string 1)))))))

(defun stex--check-setup ()
  "Verify that `flams' and sTeX are installed and new enough.
Signal `user-error' with a specific diagnosis if not."
  (let ((exe (stex--flams-executable)))
    (cond
     ((not exe)
      (user-error
       "𝖥𝖫∀𝖬∫: no `flams' executable found; set `stex-flams-executable' \
(M-x customize-group RET stex RET)"))
     (t
      (let ((flams-version (stex--flams-version)))
        (cond
         ((not flams-version)
          (user-error
           "𝖥𝖫∀𝖬∫: `%s' does not look like a flams executable" exe))
         ((not (stex--version>= flams-version stex--required-flams-version))
          (user-error
           "𝖥𝖫∀𝖬∫: flams %s is too old (need >= %s); update it or adjust \
`stex-flams-executable'"
           (mapconcat #'number-to-string flams-version ".")
           (mapconcat #'number-to-string stex--required-flams-version ".")))
         ((not (stex--has-latex-p))
          (user-error
           "𝖥𝖫∀𝖬∫: no LaTeX found; make sure `kpsewhich' is on PATH"))
         (t
          (let ((stex-version (stex--stex-version)))
            (cond
             ((not stex-version)
              (user-error
               "𝖥𝖫∀𝖬∫: sTeX package (stex.sty) not found via kpsewhich"))
             ((not (stex--version>= stex-version stex--required-stex-version))
              (user-error
               "𝖥𝖫∀𝖬∫: sTeX package %s is too old (need >= %s); update it"
               (mapconcat #'number-to-string stex-version ".")
               (mapconcat #'number-to-string
                           stex--required-stex-version ".")))))))))))
  t)

;;; eglot integration

;; A dedicated server class (rather than the generic
;; `eglot-lsp-server') so there is somewhere to stash the HTTP base
;; URL the server reports once ready; MathHub browsing needs it.
(defclass stex-eglot-server (eglot-lsp-server)
  ((http-url :initform nil :accessor stex-eglot-server-http-url))
  :documentation "Eglot server class used for FLAMS connections.")

(defun stex--eglot-contact (&optional _interactive _project)
  "Build the eglot contact list to launch `flams --lsp'."
  (let ((exe (stex--flams-executable)))
    (append (list 'stex-eglot-server exe "--lsp")
            (when stex-settings-toml (list "-c" stex-settings-toml)))))

(defconst stex--eglot-server-program-entry
  '((latex-mode LaTeX-mode) . stex--eglot-contact)
  "Entry prepended to `eglot-server-programs' by `stex-mode'.")

(cl-defmethod eglot-handle-notification
  ((server stex-eglot-server) (_method (eql flams/serverURL)) &key url)
  "Record on SERVER the URL from the flams/serverURL notification.
MathHub browsing (`stex-mathhub-open-file' etc.) talks to this URL."
  (setf (stex-eglot-server-http-url server) url))

(defun stex--preview-url (base-url doc-uri)
  "Build a browsable preview URL on BASE-URL for DOC-URI."
  (concat base-url "?uri=" (url-hexify-string doc-uri)))

;;; Local live-reload relay for previews

;; The VS Code extension refreshes an already-open preview webview in
;; place via a two-part trick, both parts purely working around
;; quirks of VS Code's own webview API (see commands.ts): (1)
;; `webview.html = ""' then `webview.html = iframeHtml(...)' again,
;; since VS Code's `Webview.html' setter is a silent no-op when
;; assigned the exact same string it already holds; (2) the generated
;; page itself does `iframe.contentWindow.location.href =
;; iframe.src', forcing the iframe to actually re-navigate even though
;; its `src' attribute looks unchanged.  Neither trick is available to
;; a real external browser tab -- there's no webview API to defeat,
;; and FLAMS's own preview page has no self-refresh wiring of its own
;; (confirmed by reading its source: no websocket/SSE tied to
;; rebuilds, just a static render).  So instead, `stex-mode' runs its
;; own tiny local relay: `stex-preview-browser' and the automatic
;; `flams/htmlResult' handling open a wrapper page *we* serve, which
;; iframes FLAMS's real preview URL and holds open a Server-Sent-
;; Events connection back to this relay; when `flams/htmlResult' fires
;; again for the same document, the relay pushes a `reload' event down
;; that connection, and the wrapper's own script does the VS-Code-
;; style "re-navigate the iframe to its own src" trick in response.
;; Net effect: a preview tab left open in any real browser updates
;; itself, the same as VS Code's embedded one does, without Emacs
;; needing to control the browser at all.
;;
;; The relay is a hand-rolled HTTP server (`make-network-process',
;; `:host 'local' so only 127.0.0.1 can ever connect -- confirmed via
;; `make-network-process's own docstring, not assumed) since pulling
;; in a real web server package for two GET routes and SSE would be
;; disproportionate.  It understands exactly two paths: `/preview'
;; (serves the wrapper page) and `/events' (the SSE stream); anything
;; else gets a 404.  Started lazily, the first time a preview is
;; actually requested; never started at all if
;; `stex-preview-live-reload' is nil.

(defvar stex--preview-relay-process nil
  "The relay's listening server process, or nil if not started.")

(defvar stex--preview-relay-sse-clients nil
  "List of open `/events' connection processes.
Each has a `stex-sse-uri' process property (set in
`stex--preview-relay-serve-events') recording which document URI it's
watching, so `stex--preview-relay-broadcast' can target the right
ones.  Pruned of dead processes as they disconnect, in
`stex--preview-relay-sentinel'.")

(defun stex--preview-relay-status-text (code)
  "Reason phrase for HTTP status CODE, for the relay's own responses."
  (pcase code (200 "OK") (400 "Bad Request") (404 "Not Found") (_ "Error")))

(defun stex--preview-relay-respond (proc code content-type body)
  "Send a complete, `Connection: close' HTTP response on PROC.
CODE is a status code, CONTENT-TYPE a MIME type (charset=utf-8 is
added automatically), BODY the response body (a string).  Closes PROC
afterward -- every non-SSE response from this relay is one-shot."
  (let ((body-bytes (encode-coding-string body 'utf-8)))
    (process-send-string
     proc
     (concat (format "HTTP/1.1 %d %s\r\n" code (stex--preview-relay-status-text code))
             (format "Content-Type: %s; charset=utf-8\r\n" content-type)
             (format "Content-Length: %d\r\n" (length body-bytes))
             "Connection: close\r\n\r\n"
             body)))
  (delete-process proc))

(defun stex--preview-relay-parse-query (query-string)
  "Parse QUERY-STRING (\"a=1&b=2\", possibly nil) into an alist.
Each value is `url-unhex-string'd; a key with no `=' gets the empty
string as its value."
  (when query-string
    (mapcar (lambda (kv)
              (let ((eq (string-search "=" kv)))
                (if eq
                    (cons (substring kv 0 eq)
                          (url-unhex-string (substring kv (1+ eq))))
                  (cons kv ""))))
            (split-string query-string "&" t))))

(defun stex--preview-relay-wrapper-html (flams-url doc-uri)
  "Return the wrapper page HTML iframing FLAMS-URL for DOC-URI.
Live-reloads via an SSE subscription to `/events?uri=DOC-URI' on this
same relay."
  (format "<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>sTeX preview</title></head>
<body style=\"margin:0;padding:0;\">
<iframe id=\"f\" src=\"%s\" style=\"border:none;width:100vw;height:100vh;\"></iframe>
<script>
var f = document.getElementById('f');
var es = new EventSource('/events?uri=%s');
es.onmessage = function (e) {
  if (e.data === 'reload') {
    f.contentWindow.location.href = f.src;
  }
};
</script>
</body></html>"
          flams-url (url-hexify-string doc-uri)))

(defun stex--preview-relay-serve-preview (proc query)
  "Respond on PROC with the wrapper page for QUERY's `base'/`uri'."
  (let ((base (cdr (assoc "base" query)))
        (uri (cdr (assoc "uri" query))))
    (if (not (and base uri))
        (stex--preview-relay-respond proc 400 "text/plain" "Missing base/uri")
      (stex--preview-relay-respond
       proc 200 "text/html"
       (stex--preview-relay-wrapper-html (stex--preview-url base uri) uri)))))

(defun stex--preview-relay-serve-events (proc query)
  "Upgrade PROC into an open SSE stream watching QUERY's `uri'.
Registers PROC in `stex--preview-relay-sse-clients'; unlike
`stex--preview-relay-respond', never closes PROC -- it stays open
until the browser tab does, fed later by
`stex--preview-relay-broadcast'."
  (process-put proc 'stex-sse-uri (cdr (assoc "uri" query)))
  (process-send-string
   proc
   (concat "HTTP/1.1 200 OK\r\n"
           "Content-Type: text/event-stream\r\n"
           "Cache-Control: no-cache\r\n"
           "Connection: keep-alive\r\n\r\n"))
  (push proc stex--preview-relay-sse-clients))

(defun stex--preview-relay-dispatch (proc request-line)
  "Route REQUEST-LINE (e.g. \"GET /preview?uri=... HTTP/1.1\") on PROC."
  (if (not (string-match "\\`GET \\([^ ]+\\) HTTP/" request-line))
      (stex--preview-relay-respond proc 400 "text/plain" "Bad Request")
    (let* ((path-and-query (split-string (match-string 1 request-line) "?"))
           (path (car path-and-query))
           (query (stex--preview-relay-parse-query (cadr path-and-query))))
      (cond
       ((equal path "/preview") (stex--preview-relay-serve-preview proc query))
       ((equal path "/events") (stex--preview-relay-serve-events proc query))
       (t (stex--preview-relay-respond proc 404 "text/plain" "Not Found"))))))

(defun stex--preview-relay-filter (proc chunk)
  "Accumulate CHUNK on PROC, dispatching once a full request has arrived.
\"Full\" means a blank line after the request line -- this relay never
expects or looks for a body, since every request it serves is a
bodyless GET."
  (process-put proc 'stex-buf (concat (or (process-get proc 'stex-buf) "") chunk))
  (let ((buf (process-get proc 'stex-buf)))
    (when (string-match "\r\n\r\n" buf)
      (stex--preview-relay-dispatch proc (car (split-string buf "\r\n"))))))

(defun stex--preview-relay-sentinel (proc _event)
  "Drop PROC from `stex--preview-relay-sse-clients' once it dies."
  (unless (process-live-p proc)
    (setq stex--preview-relay-sse-clients
          (delq proc stex--preview-relay-sse-clients))))

(defun stex--preview-relay-ensure ()
  "Start the local live-reload relay if not already running.
Return the port it's listening on (127.0.0.1 only)."
  (unless (and stex--preview-relay-process
               (process-live-p stex--preview-relay-process))
    (setq stex--preview-relay-process
          (make-network-process
           :name "stex-preview-relay"
           :service t
           :server t
           :family 'ipv4
           :host 'local
           :filter #'stex--preview-relay-filter
           :sentinel #'stex--preview-relay-sentinel
           :noquery t)))
  (cadr (process-contact stex--preview-relay-process)))

(defun stex--preview-relay-url (base-url doc-uri)
  "Return the local relay's wrapper URL for BASE-URL/DOC-URI.
Like `stex--preview-url', but through the local live-reload relay --
starts it via `stex--preview-relay-ensure' if it isn't running yet."
  (format "http://127.0.0.1:%d/preview?base=%s&uri=%s"
          (stex--preview-relay-ensure)
          (url-hexify-string base-url)
          (url-hexify-string doc-uri)))

(defun stex--preview-relay-clients-for (doc-uri)
  "Return the open relay client processes currently watching DOC-URI."
  (seq-filter (lambda (proc)
                (and (process-live-p proc)
                     (equal (process-get proc 'stex-sse-uri) doc-uri)))
              stex--preview-relay-sse-clients))

(defun stex--preview-relay-broadcast (doc-uri)
  "Push an SSE `reload' event to every open relay client watching DOC-URI.
Return the list of clients it was sent to (nil if the relay was never
started, if `stex-preview-live-reload' is nil, or if nothing is
currently watching DOC-URI) -- callers use this to tell whether an
already-open tab just got refreshed, as opposed to nothing being open
for DOC-URI at all."
  (when stex-preview-live-reload
    (let ((clients (stex--preview-relay-clients-for doc-uri)))
      (dolist (proc clients)
        (ignore-errors (process-send-string proc "data: reload\n\n")))
      clients)))

(defun stex--preview-url-for (base-url doc-uri)
  "Return the URL to `browse-url' for BASE-URL/DOC-URI.
`stex--preview-relay-url' if `stex-preview-live-reload' is non-nil
\(the default), `stex--preview-url' (FLAMS's own URL, direct, no live
reload) otherwise."
  (if stex-preview-live-reload
      (stex--preview-relay-url base-url doc-uri)
    (stex--preview-url base-url doc-uri)))

(defun stex--handle-html-result (base-url doc-uri)
  "Given BASE-URL, react to a flams/htmlResult notice about DOC-URI.
BASE-URL is the reporting server's HTTP base URL (nil if unknown);
DOC-URI is the document whose HTML just got (re)built.  Broadcasts to
any already-open live-reload relay clients for DOC-URI first (see
`stex--preview-relay-broadcast'); if that actually reached a client,
stop there -- an already-open tab just refreshed itself, so there is
nothing more to do, and `stex-preview-auto-open' popping a second, new
tab on top of it would just be a duplicate.  Only when nothing was
already open does `stex-preview-auto-open' get to open a new tab (or,
if it's nil, `stex-mode' just messages that a preview is ready)."
  (if (stex--preview-relay-broadcast doc-uri)
      (message "𝖥𝖫∀𝖬∫: HTML preview refreshed")
    (if (and base-url stex-preview-auto-open)
        (browse-url (stex--preview-url-for base-url doc-uri))
      (message "𝖥𝖫∀𝖬∫: HTML preview ready (M-x stex-preview-browser)"))))

(cl-defmethod eglot-handle-notification
  ((server stex-eglot-server) (_method (eql flams/htmlResult)) &key url)
  "Handle SERVER's notice that it has (re)built HTML for URL.
URL identifies some document, not necessarily the current buffer's
file, since the server decides when to rebuild on its own schedule."
  (stex--handle-html-result (stex-eglot-server-http-url server) url))

(defun stex--handle-update-mathhub ()
  "React to a flams/updateMathHub notice by refreshing the MathHub tree.
Only does anything if a `*sTeX MathHub*' buffer already exists --
harmless, and does nothing, otherwise."
  (when (get-buffer "*sTeX MathHub*")
    (stex-mathhub-tree)))

(cl-defmethod eglot-handle-notification
  ((_server stex-eglot-server) (_method (eql flams/updateMathHub))
   &key &allow-other-keys)
  "Refresh the MathHub tree buffer, if any, when the server signals a change.
flams sends flams/updateMathHub whenever MathHub's contents change --
e.g. after `stex-mathhub-new-archive' or an install."
  (stex--handle-update-mathhub))

;;;###autoload
(defun stex-show-call-hierarchy ()
  "Show call hierarchy for the symbol at point.
A thin wrapper around `eglot-show-call-hierarchy' (which see for how
to pick a direction with a prefix argument) that, when
`stex-call-hierarchy-side' is non-nil, shows the results in a
dedicated side window instead of wherever `display-buffer' would
otherwise put them."
  (interactive)
  (unless (fboundp 'eglot-show-call-hierarchy)
    (user-error
     "𝖥𝖫∀𝖬∫: `eglot-show-call-hierarchy' unavailable; update the eglot package"))
  (if stex-call-hierarchy-side
      (let ((display-buffer-alist
             (cons `("\\`\\*EGLOT call hierarchy for .*\\*\\'"
                     (display-buffer-in-side-window)
                     (side . ,stex-call-hierarchy-side)
                     (window-width . ,stex-call-hierarchy-width)
                     (slot . 0))
                   display-buffer-alist)))
        (call-interactively #'eglot-show-call-hierarchy))
    (call-interactively #'eglot-show-call-hierarchy)))

(defvar stex-mode-map
  (let ((map (make-sparse-keymap))
        (prefix (make-sparse-keymap)))
    (define-key prefix "c" #'stex-connect)
    (define-key prefix "f" #'stex-build-file)
    (define-key prefix "F" #'stex-build-all)
    (define-key prefix "d" #'stex-build-dashboard)
    (define-key prefix "e" #'stex-export-tex)
    (define-key prefix "E" #'stex-export-html)
    (define-key prefix "p" #'stex-preview-browser)
    (define-key prefix "o" #'stex-mathhub-open-file)
    (define-key prefix "u" #'stex-mathhub-insert-usemodule)
    (define-key prefix "s" #'stex-mathhub-search-symbols)
    (define-key prefix "S" #'stex-mathhub-search)
    (define-key prefix "t" #'stex-mathhub-tree)
    (define-key prefix "a" #'stex-mathhub-new-archive)
    (define-key prefix "U" #'stex-mathhub-update)
    (define-key prefix "h" #'stex-show-call-hierarchy)
    (define-key prefix "i" #'imenu)
    (define-key prefix "P" #'stex-toggle-prettify-symbols)
    (define-key map (kbd "C-c C-x") prefix)
    map)
  "Keymap for `stex-mode', with everything under one prefix.
Chosen prefix verified against the AUCTeX and preview.el default
keymaps (as of this writing neither binds it to anything, unlike most
of the alphabet under plain `C-c C-<letter>', which AUCTeX already
claims almost entirely; recheck if a future AUCTeX version starts
using it).
\\<stex-mode-map>\\[stex-connect]  `stex-connect'
\\[stex-build-file]  `stex-build-file'
\\[stex-build-all]  `stex-build-all'
\\[stex-build-dashboard]  `stex-build-dashboard' (opens in a browser; see
  `stex-build-auto-dashboard' to open it automatically after a build)
\\[stex-export-tex]  `stex-export-tex'
\\[stex-export-html]  `stex-export-html'
\\[stex-preview-browser]  `stex-preview-browser'
\\[stex-mathhub-open-file]  `stex-mathhub-open-file'
\\[stex-mathhub-insert-usemodule]  `stex-mathhub-insert-usemodule'
\\[stex-mathhub-search-symbols]  `stex-mathhub-search-symbols' -- fuzzy,
  incremental search over FLAMS's whole indexed MathHub (not just
  local drill-down), inserts a \\usemodule for the symbol you pick
\\[stex-mathhub-search]  `stex-mathhub-search' -- same idea, but over
  FLAMS's richer content index (documents/paragraphs/definitions/
  examples/assertions/problems, filterable by category), opens the
  file for the result you pick
\\[stex-mathhub-tree]  `stex-mathhub-tree'
\\[stex-mathhub-new-archive]  `stex-mathhub-new-archive'
\\[stex-mathhub-update]  `stex-mathhub-update' -- git-pull every local
  archive; with a prefix argument, one archive
  (`stex-mathhub-update-archive') or, with two, a whole group
  (`stex-mathhub-update-group') -- both also directly M-x-able
\\[stex-show-call-hierarchy]  `stex-show-call-hierarchy' (wraps eglot's
  own `eglot-show-call-hierarchy'; requires flams to advertise
  :callHierarchyProvider)
\\[imenu]  `imenu' (built into Emacs; eglot wires it to flams's
  documentSymbol support automatically, nothing to bind ourselves)
\\[stex-toggle-prettify-symbols]  `stex-toggle-prettify-symbols' --
  live on/off for sTeX macro glyphs, see `stex-prettify-symbols'")

;;; sTeX environment insertion (AUCTeX `C-c C-e' integration)

;; This doesn't add a command or a binding of its own -- it teaches
;; AUCTeX's own `LaTeX-environment' (already on `C-c C-e' by default)
;; about sTeX's environments, the same way a package's own
;; `TeX-add-style-hook' would.  `LaTeX-add-environments' extends the
;; *current buffer's* completion list for that command; the insertion
;; functions below just describe each environment's optional/mandatory
;; arguments so `C-c C-e' prompts for `title=', `id=', &c. instead of
;; leaving you to type `[key=val,...]{...}' out by hand.  Argument
;; lists mirror the STEX manual (chapters 6-8: Document Features,
;; Modules and Symbols, Statements) -- see `stex-doc.pdf' if present.

(defconst stex--smodule-keyval-options
  '(("title") ("style") ("id") ("ns") ("lang") ("sig"))
  "Optional keyword arguments of the `smodule' environment.")

(defconst stex--sfragment-keyval-options
  '(("id") ("short"))
  "Optional keyword arguments of the `sfragment' environment.")

(defconst stex--statement-keyval-options
  '(("for") ("style" "theorem" "lemma" "corollary" "axiom" "definition"
             "example" "counterexample")
    ("title") ("id") ("name") ("macro"))
  "Optional keyword arguments shared by `sdefinition', `sassertion',
`sexample' and `sparagraph' (STEX manual, chapter 8: Statements).")

(defconst stex--mathstructure-keyval-options
  '(("name") ("this"))
  "Optional keyword arguments of the `mathstructure' environment.")

(defconst stex--problem-keyval-options
  '(("id") ("pts") ("min") ("title"))
  "Optional keyword arguments of the `sproblem'/`subproblem' environments.")

(defconst stex--solution-keyval-options
  '(("id") ("title") ("style") ("testspace") ("answerclass"))
  "Optional keyword arguments of the `solution' environment.")

(defun stex--register-environments ()
  "Teach AUCTeX's `LaTeX-environment' command about sTeX's environments.
A no-op unless AUCTeX (not just plain Emacs `latex-mode') is loaded.
Adds to the *current buffer's* environment list only, same as any
`TeX-add-style-hook'; there is no matching \"forget\" API to undo this
when `stex-mode' is disabled again, but a few extra completion
candidates in a plain LaTeX buffer are harmless."
  (when (fboundp 'LaTeX-add-environments)
    (LaTeX-add-environments
     '("smodule" LaTeX-env-args
       [TeX-arg-key-val stex--smodule-keyval-options] "Module name")
     '("sfragment" LaTeX-env-args
       [TeX-arg-key-val stex--sfragment-keyval-options] "Section title")
     '("sparagraph" LaTeX-env-args [TeX-arg-key-val stex--statement-keyval-options])
     '("sdefinition" LaTeX-env-args [TeX-arg-key-val stex--statement-keyval-options])
     '("sassertion" LaTeX-env-args [TeX-arg-key-val stex--statement-keyval-options])
     '("sexample" LaTeX-env-args [TeX-arg-key-val stex--statement-keyval-options])
     '("mathstructure" LaTeX-env-args
       "Structure name" [TeX-arg-key-val stex--mathstructure-keyval-options])
     '("sproblem" LaTeX-env-args [TeX-arg-key-val stex--problem-keyval-options])
     '("subproblem" LaTeX-env-args [TeX-arg-key-val stex--problem-keyval-options])
     '("solution" LaTeX-env-args [TeX-arg-key-val stex--solution-keyval-options])
     ;; No special argument handling documented/needed for these --
     ;; still worth having on the `C-c C-e' completion list.
     "sproof" "subproof" "blindfragment" "hint" "exnote" "gnote")))

;;; sTeX macro insertion (AUCTeX `C-c C-m' integration)

;; Same idea as `stex--register-environments', but for macros rather
;; than environments -- `TeX-add-symbols' is AUCTeX's macro-side
;; counterpart to `LaTeX-add-environments', feeding `TeX-insert-macro'
;; (`C-c C-m' by default).  Argument lists mirror the STEX manual,
;; chapter 7 (Modules and Symbols) for `\symdecl' & co. and section 7.4
;; (Notations and Semantic Macros) for `\notation'; the `\definiendum'/
;; `\definame'/`\symref' keyval option sets were cross-checked against
;; their actual expl3 definitions (STEX manual, appendix listing the
;; package source) since the prose there undersells what they accept
;; -- e.g. `\symref' turns out to take the same optional `pre=,post='
;; arguments as `\symname', which the tutorial text alone doesn't say.

(defconst stex--symdecl-keyval-options
  '(("name") ("args") ("type") ("def") ("return")
    ("assoc" "pre" "bin" "binl" "binr" "conj")
    ("reorder") ("role"))
  "Optional keyword arguments of `\\symdecl' (and `\\symdecl*').")

(defconst stex--textsymdecl-keyval-options
  '(("type") ("def") ("return")
    ("assoc" "pre" "bin" "binl" "binr" "conj")
    ("reorder") ("role"))
  "Optional keyword arguments of `\\textsymdecl'.
Like `stex--symdecl-keyval-options', minus `args' -- a `\\textsymdecl'
symbol always has arity 0.")

(defconst stex--notation-keyval-options
  '(("prec") ("op") ("variant"))
  "Optional keyword arguments of `\\notation' (and `\\notation*').")

(defconst stex--symdef-keyval-options
  (append stex--symdecl-keyval-options stex--notation-keyval-options)
  "Optional keyword arguments of `\\symdef'.
Per the STEX manual, \\symdef \"combines the functionalities and
optional arguments of \\symdecl and \\notation\" -- hence this is just
`stex--symdecl-keyval-options' and `stex--notation-keyval-options'
appended.")

(defconst stex--symname-keyval-options
  '(("pre") ("post"))
  "Optional keyword arguments of `\\symname'/`\\sn' and `\\symref'/`\\sr'.")

(defconst stex--definiendum-keyval-options
  '(("gf") ("root"))
  "Optional keyword arguments of `\\definiendum'.
Unlike `\\definame', has no `pre'/`post' -- `\\definiendum' takes its
display text explicitly.")

(defconst stex--definame-keyval-options
  '(("pre") ("post") ("gf") ("root"))
  "Optional keyword arguments of `\\definame'.
Inherits `\\symname's `pre'/`post' plus its own `gf'/`root'.")

;; The rest of this section is a second pass filling in macros missed
;; the first time around -- found by grepping the STEX manual's own
;; command index (its final appendix) for every macro documented
;; there, then cross-checking each candidate's argument shape against
;; its expl3 `\NewDocumentCommand'/`\newcommand' definition in the
;; manual's literate-source appendix, same as the first pass.  Mostly
;; two families: `\vardef' & co. (section 7.6, Variables and
;; Sequences -- STEX's answer to "a symbol, but local and outside any
;; module") and the rest of "More on Definitions"/"More on Assertions"
;; (sections 8.1-8.2) that `\definiendum'/`\definame' only partly
;; covered.  Also a few straggling cross-reference/inclusion macros
;; from chapter 6 (Document Features) that have nothing to do with
;; symbols at all, included for the same "worth having on `C-c C-m''s
;; list" reason the plain-string environment entries above are.

(defconst stex--vardef-keyval-options
  (append stex--symdef-keyval-options '(("bind")))
  "Optional keyword arguments of `\\vardef'/`\\varseq'.
`\\symdef's options (which is in turn `\\symdecl's and `\\notation's)
plus `bind', which only variables accept -- STEX manual, section 7.6.")

(defconst stex--sref-keyval-options-1
  '(("archive") ("file") ("fallback") ("pre") ("post"))
  "`\\sref'/`\\extref's first (source-side) optional keyval group.
Confirmed from `\\stex_keys_define:nnnn{sref / 1}{...}' in the STEX
manual's literate source -- the prose alone only mentions `archive'/
`file', not `fallback'/`pre'/`post'.")

(defconst stex--sref-keyval-options-2
  '(("archive") ("file") ("title"))
  "Second (target-side) keyval group shared by `\\sref' and `\\extref'.
Optional for `\\sref', mandatory for `\\extref'.  From
`\\stex_keys_define:nnnn{sref / 2}{...}' in the STEX manual's literate
source.")

;; Forward declarations for AUCTeX symbols used outside any `fboundp'
;; guard (unlike `LaTeX-add-environments'/`TeX-add-symbols' &c. above,
;; which the byte-compiler already knows not to flag when the call is
;; textually inside its own guard) -- `stex--notation-arg-open-p' is
;; only ever reachable once AUCTeX has actually defined both, via
;; `stex--register-macros' below, but is compiled as an ordinary
;; standalone function.
(declare-function TeX-escaped-p "tex" (&optional pos))
(defvar TeX-esc)

(defconst stex--notation-arg-macros
  '("notation" "notation*" "symdef" "textsymdecl")
  "Macros whose final `{...}' argument is code, not prose.
`\\notation'/`\\notation*''s notation, `\\symdef's notation,
`\\textsymdecl's output.  Protected from paragraph-fill reflow by
`stex--in-notation-arg-p'; deliberately not `\\symdecl' (no such
argument) or `\\definiendum'/`\\definame' (their text *is* prose).")

(defun stex--skip-back-over-arg (closer)
  "Move point back over one CLOSER-delimited argument, if any.
If point is right after CLOSER (`?\\}' or `?\\]'), move point back to
just before its matching opener and return t; otherwise leave point
alone and return nil.  Shared by `stex--notation-arg-open-p' and
`stex--symbol-arg-open-p' to walk backward over the `{...}'/
`[...]' arguments preceding some brace level, looking for the macro
name that starts them."
  (when (eq (char-before) closer)
    (ignore-errors (backward-sexp) t)))

(defun stex--macro-name-before-point ()
  "If point sits right after a `\\name' macro token, return NAME.
Otherwise return nil.  Point is not moved permanently (callers wrap
this in `save-excursion' as needed)."
  (let ((name-end (point)))
    (skip-chars-backward "A-Za-z@*")
    (and (eq (char-before) (aref TeX-esc 0))
         (not (TeX-escaped-p (1- (point))))
         (buffer-substring-no-properties (point) name-end))))

(defun stex--notation-arg-open-p (open-pos)
  "Non-nil if OPEN-POS opens a `stex--notation-arg-macros' final argument.
OPEN-POS must be the buffer position of an opening brace (as found in
the third element of `syntax-ppss').  Checks what precedes it: an
optional `[...]' keyval group (skipped over), then a mandatory
`{...}' argument, then one of `stex--notation-arg-macros' -- i.e. the
exact `{arg1}[options]{arg2}' shape those macros were registered
with in `stex--register-macros', with OPEN-POS as arg2's brace."
  (and (eq (char-after open-pos) ?\{)
       (save-excursion
         (goto-char open-pos)
         (skip-chars-backward " \t\n")
         (stex--skip-back-over-arg ?\])
         (skip-chars-backward " \t\n")
         (and (stex--skip-back-over-arg ?\})
              (progn
                (skip-chars-backward " \t\n")
                (member (stex--macro-name-before-point)
                        stex--notation-arg-macros))))))

(defun stex--in-notation-arg-p ()
  "Non-nil if point is inside a protected sTeX notation/output argument.
Checks every brace level currently open around point (not just the
innermost), so it still protects e.g. \\comp{...} text nested inside
a \\notation's own argument.  Meant for `fill-nobreak-predicate' --
added there by `stex--register-macros'.  Unlike marking these macros
via `LaTeX-verbatim-macros-with-braces' (which would also disable
font-lock and macro recognition inside the argument, appropriate for
truly verbatim text like `\\lstinline' but not for this, which is
ordinary LaTeX with real macros in it), this only ever suppresses
line-fill breaks."
  (cl-some #'stex--notation-arg-open-p (nth 9 (syntax-ppss))))

;;; Folding notation/output code (AUCTeX `TeX-fold-mode' integration)

;; The same `stex--notation-arg-macros' this section protects from
;; fill also make good folding candidates: a `\notation'/`\symdef'
;; definition can run long, and once written, the interesting part to
;; see at a glance while editing surrounding text is usually the
;; notation itself, not the whole `\notation{sym}[prec=...]{...}'
;; wrapper.  `TeX-fold-mode' (AUCTeX's own construct-folding minor
;; mode, `C-c C-o C-b'/`C-c C-o C-m' &c.) already does exactly this
;; kind of thing for stock macros like `\section'/`\emph' via
;; `TeX-fold-macro-spec-list'; this just adds an entry for ours.

(defcustom stex-fold-notation-max-length 40
  "Maximum length of a folded notation/output argument's display.
Applies to `\\notation'/`\\notation*'/`\\symdef'/`\\textsymdecl' under
`TeX-fold-mode' -- see `stex--fold-notation-display'.  Longer than
this, the display is truncated with an ellipsis; the buffer text
itself is never touched, only what folding displays in its place."
  :type 'integer
  :group 'stex)

(defun stex--fold-notation-display (_name code &rest _args)
  "`TeX-fold-macro-spec-list' display function for `stex--notation-arg-macros'.
Called by `TeX-fold-mode' with each macro's mandatory arguments; for
these macros that's `(mname code)', per the `{arg1}[options]{arg2}'
shape they were registered with in `stex--register-macros' -- _NAME is
ignored, CODE (the notation/output argument, the same one
`stex--in-notation-arg-p' protects from fill) is what gets shown,
whitespace-collapsed onto one line and truncated to
`stex-fold-notation-max-length' with an ellipsis if longer."
  (let ((flat (string-trim (replace-regexp-in-string "[ \t\n]+" " " code))))
    (if (> (length flat) stex-fold-notation-max-length)
        (concat (substring flat 0 stex-fold-notation-max-length) "…")
      flat)))

(defun stex--register-fold ()
  "Teach AUCTeX's `TeX-fold-mode' to fold `stex--notation-arg-macros'.
Displays each one's notation/output argument via
`stex--fold-notation-display' instead of AUCTeX's generic \"[m]\"
placeholder.  A no-op unless `tex-fold' is available to load -- note
this is `(require \\='tex-fold nil t)', not an `fboundp' check on
`TeX-fold-mode' like the guards elsewhere in this file use: AUCTeX
autoloads that *function* even before `tex-fold.el' itself has
loaded, but `TeX-fold-macro-spec-list' (a plain variable, not
autoloaded) stays void until it actually has -- confirmed the hard
way, `fboundp'-guarding this the same way broke with a real
`void-variable' error the first time this ran without `tex-fold'
already loaded some other way.  Adds to the *current buffer's*
`TeX-fold-macro-spec-list' only, same caveats as
`stex--register-environments': no \"forget\" API to undo this when
`stex-mode' is disabled again, and -- specific to this variable, per
its own docstring -- `TeX-fold-mode' must be (re)started for a change
to it to actually take effect, so a `TeX-fold-mode' already turned on
in this buffer before `stex-mode' enables won't see this until
toggled off and back on."
  (when (require 'tex-fold nil t)
    (add-to-list (make-local-variable 'TeX-fold-macro-spec-list)
                 (list (cons #'stex--fold-notation-display '(1 . 2))
                       stex--notation-arg-macros))))

;;; sTeX macro prettification (prettify-symbols-mode)

;; AUCTeX already sets up `prettify-symbols-alist' for every
;; `LaTeX-mode'/`TeX-mode' buffer -- `TeX-common-initialization' in
;; tex.el does `(setq-local prettify-symbols-alist
;; tex--prettify-symbols-alist)', the same ~600-entry table of
;; standard LaTeX math macros (`\alpha', `\rightarrow', `\forall', &c.)
;; that plain Emacs's own tex-mode.el ships -- it just isn't turned on
;; by default (`prettify-symbols-mode' is a plain toggle, `M-x
;; prettify-symbols-mode' or a `LaTeX-mode-hook' entry). None of that
;; table's entries are sTeX-specific, though: `\importmodule',
;; `\symdecl', `\symdef' and the rest of this package's own macros
;; (`stex--register-macros') look exactly as typed, backslash and all.
;; `stex-prettify-symbols-alist' below extends (never replaces) that
;; existing table with entries for those, so `prettify-symbols-mode'
;; renders them as compact glyphs too, same mechanism. The glyph
;; choices are this package's own curated picks (grouped by what the
;; macro *does* -- declares a symbol, defines its notation, references
;; one, imports a module, &c.), not derived from any FLAMS/vscode
;; source; customize `stex-prettify-symbols-alist' to change them.
;;
;; `prettify-symbols-mode' itself and the sTeX-specific extension are
;; two independent knobs: `stex-mode' always turns the mode on, but
;; whether `stex-prettify-symbols-alist' starts appended is controlled
;; separately by `stex-prettify-symbols' -- and, unlike most of this
;; package's other buffer-local registrations (`TeX-add-symbols' &c.,
;; which have no "forget" API), this one can be toggled live at any
;; time afterwards with `stex-toggle-prettify-symbols', without ever
;; touching `prettify-symbols-mode' itself or AUCTeX's own standard-
;; LaTeX-math entries.

(defcustom stex-prettify-symbols t
  "Whether sTeX's own macros start out prettified in a `stex-mode' buffer.
`stex-mode' always turns on `prettify-symbols-mode' itself (see
`stex--register-prettify-symbols'); this only controls whether
`stex-prettify-symbols-alist' is appended to `prettify-symbols-alist'
from the start.  Toggle it live in a given buffer with
`stex-toggle-prettify-symbols' -- that command makes this
buffer-local, so the choice sticks even across disabling and
re-enabling `stex-mode' in that buffer."
  :type 'boolean
  :group 'stex)

(defcustom stex-prettify-symbols-alist
  '(;; Module system: import (and re-export), use (no re-export),
    ;; require as a build dependency.
    ("\\importmodule" . ?⇒)
    ("\\usemodule" . ?→)
    ("\\requiremodule" . ?↠)
    ;; Declares a new symbol.  Starred/textual variants get a hollow
    ;; or alternate diamond, matching "still declares, slightly
    ;; different shape" rather than an unrelated glyph.
    ("\\symdecl" . ?◆)
    ("\\symdecl*" . ?◇)
    ("\\textsymdecl" . ?⬧)
    ;; Defines a symbol's (or variable's) usable notation.
    ("\\symdef" . ?✎)
    ("\\vardef" . ?✐)
    ;; Defines notation for an already-declared symbol/variable.
    ("\\notation" . ?❖)
    ("\\notation*" . ?◈)
    ("\\varnotation" . ?◈)
    ("\\defnotation" . ?❖)
    ;; References an existing symbol/variable by name.
    ("\\symref" . ?↪)
    ("\\varref" . ?↩)
    ;; Marks text as defining a term.
    ("\\definiendum" . ?‣)
    ("\\definame" . ?‣)
    ("\\Definame" . ?‣)
    ;; Splices another file's content in by reference.
    ("\\inputref" . ?↴)
    ("\\mhinput" . ?↴)
    ;; Cross-references to a labeled spot, in- or out-of-document.
    ("\\sref" . ?§)
    ("\\extref" . ?⇗))
  "Alist of (MACRO-STRING . CHARACTER) added to `prettify-symbols-alist'.
See the Commentary above this variable's definition for how it's used
and where the glyph choices come from.  Each entry follows
`prettify-symbols-alist''s own format, so it can be edited/extended
the same way."
  :type '(alist :key-type string :value-type character)
  :group 'stex)

(defvar-local stex--prettify-symbols-was-on nil
  "Whether `prettify-symbols-mode' was already on before `stex-mode' enabled.
Set by `stex--register-prettify-symbols'; read on `stex-mode' disable
so a mode the user had already turned on themselves isn't switched
back off underneath them.")

(defun stex--prettify-symbols-refresh ()
  "Restart `prettify-symbols-mode' to pick up a `prettify-symbols-alist' edit.
Per its own docstring, a running `prettify-symbols-mode' doesn't
re-scan `prettify-symbols-alist' on its own once it's already
fontified a buffer -- toggling it off and back on is the standard fix,
the same restart caveat `stex--register-fold' documents for
`TeX-fold-macro-spec-list'.  A no-op if `prettify-symbols-mode' isn't
even on."
  (when prettify-symbols-mode
    (prettify-symbols-mode -1)
    (prettify-symbols-mode 1)))

(defun stex--register-prettify-symbols ()
  "Turn on `prettify-symbols-mode', with sTeX glyphs if `stex-prettify-symbols'.
Always turns on `prettify-symbols-mode' itself, independent of
`stex-prettify-symbols' -- see the Commentary above
`stex-prettify-symbols' for why those are two separate knobs.  Appends
`stex-prettify-symbols-alist' rather than replacing
`prettify-symbols-alist' outright, so AUCTeX's own standard-LaTeX-math
entries stay in effect too."
  (setq stex--prettify-symbols-was-on prettify-symbols-mode)
  (when stex-prettify-symbols
    (setq-local prettify-symbols-alist
                (append stex-prettify-symbols-alist prettify-symbols-alist)))
  (prettify-symbols-mode 1))

;;;###autoload
(defun stex-toggle-prettify-symbols ()
  "Toggle whether sTeX's own macros are prettified, live, in this buffer.
Leaves `prettify-symbols-mode' itself, and AUCTeX's own standard-
LaTeX-math entries in `prettify-symbols-alist', alone either way --
only adds or removes `stex-prettify-symbols-alist' (via
`stex--prettify-symbols-refresh' to make the change actually visible)
and makes `stex-prettify-symbols' buffer-local so the new state
sticks.  See the Commentary above `stex-prettify-symbols' for how
`stex-mode' picks the starting state."
  (interactive)
  (setq-local prettify-symbols-alist
              (if stex-prettify-symbols
                  (seq-difference prettify-symbols-alist
                                   stex-prettify-symbols-alist #'equal)
                (append stex-prettify-symbols-alist prettify-symbols-alist)))
  (setq-local stex-prettify-symbols (not stex-prettify-symbols))
  (stex--prettify-symbols-refresh)
  (message "𝖥𝖫∀𝖬∫: sTeX macro prettification %s"
           (if stex-prettify-symbols "enabled" "disabled")))

;;; Local symbol-name completion

;; FLAMS's own `completion' LSP request is a permanent stub as of this
;; writing (confirmed by reading source/lsp/src/implementation.rs in
;; the FLAMS repository: `impl_request!(!completion = Completion =>
;; (None));' -- always returns nothing, no matter what), so eglot has
;; nothing to offer for `\symref'/`\symname'/&c.'s symbol argument.
;; This is a local, buffer-scanning stand-in: it collects symbol names
;; declared via `\symdecl'/`\symdecl*'/`\textsymdecl'/`\symdef' in the
;; current buffer, plus (best-effort) in any file referenced via a
;; plain `\usemodule{X}'/`\importmodule{X}' (no `[archive]' override --
;; resolving that needs a live MathHub connection, which a
;; `completion-at-point-functions' entry must never block on; see
;; `stex--resolve-local-usemodule-files').  It does not resolve
;; transitively (a used module's own `\usemodule's aren't followed),
;; and does not honor an explicit `name=' override in a `\symdecl's
;; options -- both deliberately out of scope, not oversights.

(defconst stex--symdecl-macro-names '("symdecl" "textsymdecl" "symdef")
  "Base macro names, without a trailing `*', that declare a new symbol.
Each one's own first `{...}' argument is the declared name -- see
`stex--symdecl-names-in-current-buffer'.")

(defconst stex--symbol-arg-macros
  '("symref" "sr" "symname" "sn" "symuse" "definiendum" "definame")
  "Macros whose first mandatory argument is a symbol name.
Unlike `stex--notation-arg-macros', this is the *first* `{...}'
argument (after skipping a possible leading `[options]'), not the
last -- see `stex--symbol-arg-open-p'.")

(defun stex--symdecl-names-in-current-buffer (&optional macros-only)
  "Return symbol names declared in the current buffer, in order.
Scans for `stex--symdecl-macro-names' (and `\\symdecl*'), taking each
one's own first `{...}' argument as the declared name.  When
MACROS-ONLY is non-nil, skip `\\symdecl*' declarations -- the starred
variant explicitly does *not* generate a same-named semantic macro
\(STEX manual: \"does not generate a semantic macro\"), unlike plain
`\\symdecl'/`\\textsymdecl'/`\\symdef', so a symbol declared that way has
no `\\name' macro to complete to, only a bare name to reference via
`\\symname'/`\\sr' & co."
  (let (names (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (concat "\\\\\\(?:" (regexp-opt stex--symdecl-macro-names) "\\)"
                      "\\(\\*?\\)[ \t\n]*{\\([^{}]*\\)}")
              nil t)
        (unless (and macros-only (equal (match-string-no-properties 1) "*"))
          (push (match-string-no-properties 2) names))))
    (nreverse names)))

(defun stex--symdecl-names-in-file (file &optional macros-only)
  "Like `stex--symdecl-names-in-current-buffer', applied to FILE.
MACROS-ONLY is passed through -- see `stex--symdecl-names-in-current-buffer'.
Reads FILE into a throwaway buffer rather than visiting it, so this
never adds to `buffer-list' or triggers major-mode/`stex-mode' setup.
Returns nil (rather than erroring) if FILE can't be read."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (stex--symdecl-names-in-current-buffer macros-only))
    (error nil)))

(defun stex--local-usemodule-targets ()
  "Return base names from this buffer's archive-less usemodule macros.
Specifically, the `{X}' of every `\\usemodule{X}'/`\\importmodule{X}'
in the current buffer -- deliberately not `\\usemodule[archive]{X}':
the `[...]' before `{X}' makes the regexp not match at all, which is
exactly the filtering wanted here, not a bug.  Any `?Selector' module
suffix (STEX's way of naming one module among several in a file, e.g.
`\\usemodule{latex?LaTeX}') is stripped, since it selects a module
within the target file rather than changing which file to look in."
  (let (targets (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "\\\\\\(?:usemodule\\|importmodule\\)[ \t\n]*{\\([^{}]*\\)}"
              nil t)
        (push (car (split-string (match-string-no-properties 1) "\\?"))
              targets)))
    (nreverse targets)))

(defun stex--resolve-local-usemodule-files ()
  "Resolve `stex--local-usemodule-targets' to actual sibling files.
Looks next to the current file for `TARGET.tex' or a language-suffixed
`TARGET.XX.tex' (STEX's file-naming convention, e.g. `Foo.en.tex');
skips targets that don't exist as either.  nil if the buffer isn't
visiting a file at all."
  (when buffer-file-name
    (let ((dir (file-name-directory buffer-file-name)))
      (mapcan
       (lambda (base)
         (append
          (file-expand-wildcards (expand-file-name (concat base ".tex") dir))
          (file-expand-wildcards (expand-file-name (concat base ".??.tex") dir))))
       (stex--local-usemodule-targets)))))

(defun stex--known-symbol-names (&optional macros-only)
  "All symbol names available for completion at point.
This buffer's own declarations plus those in
`stex--resolve-local-usemodule-files', deduplicated.  MACROS-ONLY is
passed through -- see `stex--symdecl-names-in-current-buffer'."
  (delete-dups
   (append (stex--symdecl-names-in-current-buffer macros-only)
           (mapcan (lambda (f) (stex--symdecl-names-in-file f macros-only))
                    (stex--resolve-local-usemodule-files)))))

(defun stex--symbol-arg-open-p (open-pos)
  "Non-nil if OPEN-POS opens a `stex--symbol-arg-macros' symbol argument.
Mirrors `stex--notation-arg-open-p', but for the *first* mandatory
argument (skipping only a possible leading `[options]', no preceding
mandatory argument to also skip)."
  (and (eq (char-after open-pos) ?\{)
       (save-excursion
         (goto-char open-pos)
         (skip-chars-backward " \t\n")
         (stex--skip-back-over-arg ?\])
         (skip-chars-backward " \t\n")
         (member (stex--macro-name-before-point) stex--symbol-arg-macros))))

(defun stex--symbol-completion-at-point ()
  "`completion-at-point-functions' entry for sTeX symbol arguments.
Offers `stex--known-symbol-names' when point is inside the symbol
argument of `\\symref'/`\\sr'/`\\symname'/`\\sn'/`\\symuse'/
`\\definiendum'/`\\definame'.  `:exclusive' is `no' so, wherever this
doesn't apply (or its candidates don't match what's typed), eglot's
own `completion-at-point' still gets a chance -- currently offering
nothing either way, per the note above, but that's FLAMS's doing, not
this function's."
  (let ((open-pos (cl-find-if #'stex--symbol-arg-open-p (nth 9 (syntax-ppss)))))
    (when open-pos
      (let ((beg (1+ open-pos)))
        (list beg (save-excursion (goto-char beg) (skip-chars-forward "^{}") (point))
              (stex--known-symbol-names) :exclusive 'no)))))

(defun stex--macro-prefix-bounds ()
  "If point is right after a partial macro name, return its (BEG . END).
I.e. point is positioned as `\\NAME', NAME possibly empty, being typed
-- BEG is right after the backslash, END is point.  Return nil
otherwise."
  (save-excursion
    (let ((end (point)))
      (skip-chars-backward "A-Za-z@*")
      (when (and (eq (char-before) (aref TeX-esc 0))
                 (not (TeX-escaped-p (1- (point)))))
        (cons (point) end)))))

(defun stex--macro-name-completion-at-point ()
  "`completion-at-point-functions' entry completing sTeX symbols as macros.
Offers `\\NAME' for every symbol NAME declared in scope that also
generates a same-named semantic macro (`stex--known-symbol-names' with
MACROS-ONLY set -- skips bare `\\symdecl*' declarations, which don't).
Complementary to `stex--symbol-completion-at-point': that one offers
the bare NAME inside `\\symref' & co.'s own symbol argument; this one
offers NAME as a macro invocation anywhere else (the backslash is
already in the buffer -- `stex--macro-prefix-bounds' excludes it from
the replaced region, same as it would for any other macro name), which
is what a non-starred `\\symdecl'/`\\textsymdecl'/`\\symdef' declaration
actually produces (STEX manual, section 7.2) but which AUCTeX's own
macro completion has no way to know about, since it isn't declared via
`\\newcommand'/`\\def'."
  (let ((bounds (stex--macro-prefix-bounds)))
    (when bounds
      (list (car bounds) (cdr bounds) (stex--known-symbol-names t) :exclusive 'no))))

(defun stex--register-macros ()
  "Teach AUCTeX's `TeX-insert-macro' command about sTeX's macros.
A no-op unless AUCTeX is loaded.  Adds to the *current buffer's* macro
list only -- see `stex--register-environments' for the same idea
applied to environments, including the caveat about there being no way
to undo this when `stex-mode' is disabled again.  Also adds
`stex--in-notation-arg-p' to `fill-nobreak-predicate', same as
AUCTeX's own `LaTeX-common-initialization' does for `\\verb'-like
macros, so `M-q'/auto-fill never rewraps a notation/output argument.
Also adds `stex--symbol-completion-at-point' and
`stex--macro-name-completion-at-point' to `completion-at-point-functions',
for symbol/macro-name completion where `flams' itself currently offers
none -- see those functions."
  (when (fboundp 'TeX-add-symbols)
    (add-to-list (make-local-variable 'fill-nobreak-predicate)
                 #'stex--in-notation-arg-p t)
    (add-hook 'completion-at-point-functions
              #'stex--symbol-completion-at-point nil t)
    (add-hook 'completion-at-point-functions
              #'stex--macro-name-completion-at-point nil t)
    (TeX-add-symbols
     '("symdecl" "Macro name" [TeX-arg-key-val stex--symdecl-keyval-options])
     '("symdecl*" "Macro name" [TeX-arg-key-val stex--symdecl-keyval-options])
     '("textsymdecl" "Macro name"
       [TeX-arg-key-val stex--textsymdecl-keyval-options] "Output")
     '("symdef" "Macro name"
       [TeX-arg-key-val stex--symdef-keyval-options] "Notation")
     '("notation" "Symbol" [TeX-arg-key-val stex--notation-keyval-options] "Notation")
     '("notation*" "Symbol" [TeX-arg-key-val stex--notation-keyval-options] "Notation")
     '("symref" [TeX-arg-key-val stex--symname-keyval-options] "Symbol" "Text")
     '("sr" [TeX-arg-key-val stex--symname-keyval-options] "Symbol" "Text")
     '("symname" [TeX-arg-key-val stex--symname-keyval-options] "Symbol")
     '("sn" [TeX-arg-key-val stex--symname-keyval-options] "Symbol")
     '("symuse" "Symbol")
     '("definiendum" [TeX-arg-key-val stex--definiendum-keyval-options]
       "Symbol" "Text")
     '("definame" [TeX-arg-key-val stex--definame-keyval-options] "Symbol")
     ;; Second pass -- see the comment above `stex--vardef-keyval-options'.
     '("Symname" [TeX-arg-key-val stex--symname-keyval-options] "Symbol")
     ;; \sns/\Sns hardcode post=s (they're literally `\def\Sns{\Symname[post=s]}'
     ;; in the source, not independent `\NewDocumentCommand's), so unlike
     ;; \sn/\Sn above they take only the plain symbol argument, no keyval.
     '("sns" "Symbol")
     '("Sns" "Symbol")
     '("srefsym" "Symbol" "Text")
     '("srefsymuri" "Symbol URI" "Text")
     '("vardef" "Macro name" [TeX-arg-key-val stex--vardef-keyval-options] "Notation")
     '("varnotation" "Variable"
       [TeX-arg-key-val stex--notation-keyval-options] "Notation")
     '("varseq" "Macro name" [TeX-arg-key-val stex--vardef-keyval-options]
       "Range" "Notation")
     '("svar" ["Name"] "Text")
     '("varbind" "Variables (comma-separated)")
     '("varref" [TeX-arg-key-val stex--symname-keyval-options] "Variable" "Text")
     '("varname" [TeX-arg-key-val stex--symname-keyval-options] "Variable")
     '("Varname" [TeX-arg-key-val stex--symname-keyval-options] "Variable")
     '("Definame" [TeX-arg-key-val stex--definame-keyval-options] "Symbol")
     '("defnotation" "Notation")
     '("definiens" ["Symbol"] "Text")
     '("premise" ["Variable"] "Text")
     '("conclusion" ["Symbol"] "Text")
     '("comp" "Notation component")
     '("maincomp" "Notation component")
     '("setnotation" "Symbol" "Notation id")
     '("arg" ["Argument number"] "Text")
     '("arg*" ["Argument number"] "Text")
     '("sref" [TeX-arg-key-val stex--sref-keyval-options-1] "Label"
       [TeX-arg-key-val stex--sref-keyval-options-2])
     ;; \extref's third argument is the same key=val shape as \sref's
     ;; second, but MANDATORY (STEX manual: "with the third argument
     ;; mandatory") -- so it's given here as a plain (not `[...]'-wrapped)
     ;; list element, which is what makes `TeX-parse-argument' insert it
     ;; in braces instead of brackets.
     '("extref" [TeX-arg-key-val stex--sref-keyval-options-1] "Label"
       (TeX-arg-key-val stex--sref-keyval-options-2))
     '("srefsetin" ["Archive"] "File" "Title")
     '("sreflabel" "Label")
     '("inputref" ["Archive"] "File")
     '("mhinput" ["Archive"] "File")
     '("requiremodule" "Module"))))

;;;###autoload
(define-minor-mode stex-mode
  "Minor mode connecting the current buffer to the FLAMS/sTeX LSP server.

Enabling this in a `latex-mode'/`LaTeX-mode' buffer makes eglot launch
`flams --lsp' for it (ahead of any other server configured for that
mode in this buffer) and makes `stex-build-file', `stex-build-all',
`stex-export-tex' and `stex-export-html' available.  It also teaches
AUCTeX's `LaTeX-environment' command about sTeX environments like
`smodule', `sparagraph' and `sdefinition' (see
`stex--register-environments') and its `TeX-insert-macro' command
about sTeX macros like `\\symdecl', `\\notation' and `\\symref' (see
`stex--register-macros'), and teaches `TeX-fold-mode' to fold
`\\notation'/`\\symdef'/`\\textsymdecl' to a short label instead of
AUCTeX's generic placeholder (see `stex--register-fold').  It also
turns on `prettify-symbols-mode' (always, on top of whatever AUCTeX
already put in `prettify-symbols-alist' for standard LaTeX math),
starting with glyphs for sTeX's own macros too unless
`stex-prettify-symbols' is nil; either way, `stex-toggle-prettify-symbols'
flips just that sTeX-specific part live, any time, without touching
`prettify-symbols-mode' itself.  See `stex-mode-map' for the full
command list and its shared prefix."
  :lighter " sTeX"
  :keymap stex-mode-map
  (if stex-mode
      (condition-case err
          (progn
            (stex--check-setup)
            (setq-local eglot-server-programs
                        (cons stex--eglot-server-program-entry
                              eglot-server-programs))
            (stex--register-environments)
            (stex--register-macros)
            (stex--register-fold)
            (stex--register-prettify-symbols)
            (eglot-ensure))
        (error
         (setq stex-mode nil)
         (signal (car err) (cdr err))))
    (kill-local-variable 'eglot-server-programs)
    (when stex-prettify-symbols
      (setq-local prettify-symbols-alist
                  (seq-difference prettify-symbols-alist
                                   stex-prettify-symbols-alist #'equal)))
    (unless stex--prettify-symbols-was-on
      (prettify-symbols-mode -1))))

;;;###autoload
(defun stex-connect ()
  "Verify setup and (re)connect the current buffer to `flams'."
  (interactive)
  (stex--check-setup)
  (unless stex-mode
    (stex-mode 1))
  (eglot-ensure))

(defun stex--current-server ()
  "Return the current buffer's eglot server, or signal `user-error'."
  (or (eglot-current-server)
      (user-error "𝖥𝖫∀𝖬∫: not connected; run `M-x stex-connect' first")))

(defun stex--server-http-url ()
  "Return the current buffer's flams HTTP base URL.
Signal `user-error' if not connected or the server hasn't reported
its URL yet."
  (let ((server (stex--current-server)))
    (or (and (stex-eglot-server-p server)
             (stex-eglot-server-http-url server))
        (user-error
         "𝖥𝖫∀𝖬∫: server hasn't reported its HTTP URL yet; wait a moment and retry"))))

;;; Standalone connection (MathHub browsing without a visited .tex file)

(defun stex--live-stex-server-p (server)
  "Return non-nil if SERVER is a live (running) `stex-eglot-server'."
  (and (stex-eglot-server-p server) (jsonrpc-running-p server)))

(defun stex--find-live-server ()
  "Return any live `stex-eglot-server', or nil if none is connected.
Prefers the current buffer's server; otherwise scans every project's
servers, so this finds a connection made from a completely different
buffer (including the hidden one `stex--launch-standalone-server'
uses)."
  (or (let ((s (eglot-current-server)))
        (and (stex--live-stex-server-p s) s))
      (and (boundp 'eglot--servers-by-project)
           (cl-loop for servers being the hash-values of eglot--servers-by-project
                    thereis (cl-find-if #'stex--live-stex-server-p servers)))))

(defun stex--launch-standalone-server ()
  "Start connecting to `flams' against `stex-mathhub-root'.
No visited file is involved -- this is for MathHub browsing when
nothing is connected anywhere yet.  Does not wait for the connection;
see `stex--ensure-mathhub-server'.

This calls eglot's own internal `eglot--connect' directly rather than
the usual `eglot-mode'/`eglot-ensure' path, because `eglot-ensure'
defers connecting to the next `post-command-hook' run -- which never
fires here, since nothing returns to the top-level command loop
between this call and the caller polling for the result.  Verified
against the bundled eglot's (MANAGED-MODES PROJECT CLASS CONTACT
LANGUAGE-IDS) signature by reading eglot.el directly; if a future
eglot version changes it, the `fboundp' guard below at least fails
with a clear message instead of a cryptic wrong-number-of-arguments
error."
  (unless stex-mathhub-root
    (user-error
     "𝖥𝖫∀𝖬∫: no flams connection, and `stex-mathhub-root' is unset; \
set it (M-x customize-group RET stex RET) or open a .tex file with `stex-mode' first"))
  (unless (file-directory-p stex-mathhub-root)
    (user-error "𝖥𝖫∀𝖬∫: `stex-mathhub-root' (%s) is not a directory"
                stex-mathhub-root))
  (unless (fboundp 'eglot--connect)
    (user-error
     "𝖥𝖫∀𝖬∫: this Emacs's eglot lacks `eglot--connect'; open a .tex file with `stex-mode' instead"))
  (stex--check-setup)
  (with-current-buffer (get-buffer-create " *stex-mathhub-connection*")
    (setq default-directory (file-name-as-directory (expand-file-name stex-mathhub-root)))
    (unless (eq major-mode 'latex-mode)
      (latex-mode))
    (let ((eglot-sync-connect nil)) ; we poll ourselves in stex--ensure-mathhub-server
      (eglot--connect '(latex-mode LaTeX-mode) (eglot--current-project)
                       'stex-eglot-server (stex--eglot-contact)
                       ;; A list of language ids parallel to managed-modes,
                       ;; not an alist -- confirmed via eglot--connect's own
                       ;; (cl-loop for m in managed-modes for l in language-ids
                       ;; collect (cons m l)).
                       '("latex" "latex")))))

(defun stex--poll-until (predicate timeout message)
  "Call PREDICATE repeatedly until it's non-nil or TIMEOUT seconds pass.
Shows MESSAGE meanwhile.  Return PREDICATE's value, or nil on
timeout.  Uses `sit-for', so `C-g' aborts it like any blocking Emacs
operation, and process output/notifications are processed normally
while waiting."
  (let ((deadline (+ (float-time) timeout))
        result)
    (while (and (not (setq result (funcall predicate)))
                (< (float-time) deadline))
      (message "%s" message)
      (sit-for 0.2))
    result))

(defun stex--ensure-mathhub-server ()
  "Return a live `stex-eglot-server' with a known HTTP URL.
Reuses any already-connected one (from a real `stex-mode' buffer,
this one or any other); otherwise launches a standalone connection
against `stex-mathhub-root' and waits (up to
`stex-mathhub-connect-timeout' seconds, twice over: once for the
connection itself, once for it to report its HTTP URL) for it to
come up."
  (let ((server (stex--find-live-server)))
    (unless server
      (stex--launch-standalone-server)
      (setq server
            (or (stex--poll-until #'stex--find-live-server
                                   stex-mathhub-connect-timeout
                                   "𝖥𝖫∀𝖬∫: waiting for flams to initialize...")
                (user-error "𝖥𝖫∀𝖬∫: flams didn't initialize within %ss"
                            stex-mathhub-connect-timeout))))
    (unless (stex-eglot-server-http-url server)
      (unless (stex--poll-until (lambda () (stex-eglot-server-http-url server))
                                 stex-mathhub-connect-timeout
                                 "𝖥𝖫∀𝖬∫: waiting for flams to report its HTTP URL...")
        (user-error "𝖥𝖫∀𝖬∫: flams didn't report its HTTP URL within %ss"
                    stex-mathhub-connect-timeout)))
    server))

(defun stex--mathhub-base-url ()
  "Return the flams HTTP base URL to use for MathHub browsing.
Unlike `stex--server-http-url' (build/export/preview, which
inherently need a real visited file), this launches a standalone
connection via `stex--ensure-mathhub-server' if nothing is connected
anywhere yet."
  (stex-eglot-server-http-url (stex--ensure-mathhub-server)))

(defun stex--buffer-uri ()
  "Return the current buffer file's LSP URI, or signal `user-error'."
  (unless buffer-file-name
    (user-error "𝖥𝖫∀𝖬∫: buffer is not visiting a file"))
  (eglot-path-to-uri buffer-file-name))

(defun stex--dashboard-url (base &optional page)
  "Return the URL of FLAMS's build dashboard at BASE.
PAGE selects a sub-page, e.g. \"queue\" for the live build queue;
omit (or nil) for the general dashboard landing page.  FLAMS serves
this directly over HTTP -- it's the same page the VS Code extension
embeds in a webview panel, just an ordinary URL here."
  (concat (string-remove-suffix "/" base) "/dashboard/" (or page "")))

(defun stex--handle-build-request-result (base _result)
  "Given BASE, the server's HTTP base URL (or nil), handle a build success.
A named top-level function, not a closure -- see
`stex--mathhub-tree-expand' for why, and how BASE gets bound in via
`apply-partially' instead.  Opens the build-queue dashboard per
`stex-build-auto-dashboard' when BASE is known; a pure-LSP build
request (the usual case right after connecting, before FLAMS has
reported its HTTP URL) just gets the message."
  (message "𝖥𝖫∀𝖬∫: build queued")
  (when (and base stex-build-auto-dashboard)
    (browse-url (stex--dashboard-url base "queue"))))

(defun stex--build-request (method)
  "Send build request METHOD (\"flams/buildOne\" or \"flams/buildAll\").
Pure LSP, same as always -- the HTTP base URL (needed only to maybe
open the dashboard afterward, see `stex--handle-build-request-result')
is read opportunistically and left nil rather than waited for, so a
build never blocks on or requires the server having reported it yet."
  (let* ((server (stex--current-server))
         (base (and (stex-eglot-server-p server)
                    (stex-eglot-server-http-url server)))
         (uri (stex--buffer-uri)))
    (jsonrpc-async-request
     server method (list :uri uri)
     :success-fn (apply-partially #'stex--handle-build-request-result base)
     :error-fn (jsonrpc-lambda (&key message &allow-other-keys)
                 (message "𝖥𝖫∀𝖬∫: build request failed: %s" message)))))

;;;###autoload
(defun stex-build-file ()
  "Ask FLAMS to build the file visited by the current buffer."
  (interactive)
  (stex--build-request "flams/buildOne"))

;;;###autoload
(defun stex-build-all ()
  "Ask FLAMS to recursively build starting from the current file."
  (interactive)
  (stex--build-request "flams/buildAll"))

;;;###autoload
(defun stex-build-dashboard ()
  "Open FLAMS's build dashboard in a browser.
This is the same live build-queue/log page the VS Code extension
shows in a webview panel -- FLAMS serves it directly over HTTP, so
`stex-mode' just points your browser at it (no in-Emacs webview
rendering, same tradeoff as `stex-preview-browser')."
  (interactive)
  (browse-url (stex--dashboard-url (stex--server-http-url))))

(defun stex--export-request (method prompt)
  "Send export request METHOD, to a directory chosen via PROMPT."
  (let* ((server (stex--current-server))
         (uri (stex--buffer-uri))
         (target (read-directory-name prompt)))
    (jsonrpc-notify server method (list :uri uri :target target))
    (message "𝖥𝖫∀𝖬∫: export to %s requested" target)))

;;;###autoload
(defun stex-export-tex ()
  "Export the current file as a standalone .tex package."
  (interactive)
  (stex--export-request "flams/standaloneExport"
                         "Export packaged standalone tex to directory: "))

;;;###autoload
(defun stex-export-html ()
  "Export the current file as standalone HTML."
  (interactive)
  (stex--export-request "flams/htmlExport"
                         "Export packaged standalone HTML to directory: "))

(defun stex--handle-preview-request-result (base result)
  "Given BASE, the server's HTTP base URL, handle a flams/htmlRequest RESULT.
For `stex-preview-browser'.  A named top-level function, not a
closure -- see `stex--mathhub-tree-expand' for why, and how BASE gets
bound in via `apply-partially' instead."
  (if (and (stringp result) (not (string-empty-p result)))
      (browse-url (stex--preview-url-for base result))
    (message "𝖥𝖫∀𝖬∫: no preview available; building may have failed")))

;;;###autoload
(defun stex-preview-browser ()
  "Request an HTML preview of the current file and open it in a browser."
  (interactive)
  (let ((server (stex--current-server))
        (base (stex--server-http-url))
        (uri (stex--buffer-uri)))
    (message "𝖥𝖫∀𝖬∫: requesting preview...")
    (jsonrpc-async-request
     server "flams/htmlRequest" (list :uri uri)
     :success-fn (apply-partially #'stex--handle-preview-request-result base)
     :error-fn (jsonrpc-lambda (&key message &allow-other-keys)
                 (message "𝖥𝖫∀𝖬∫: preview request failed: %s" message)))))

;;; MathHub browsing (local archives only)

(defun stex--http-post (base-url endpoint params)
  "Synchronously POST to BASE-URL/ENDPOINT with PARAMS, return parsed JSON.
PARAMS is an alist of (STRING . STRING); entries with a nil value are
omitted.  The response body is parsed with `json-parse-string', using
alists for objects and lists for arrays."
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          '(("Content-Type" . "application/x-www-form-urlencoded")))
         (url-request-data
          (mapconcat
           (lambda (kv)
             (concat (url-hexify-string (car kv)) "="
                     (url-hexify-string (cdr kv))))
           (seq-filter #'cdr params)
           "&"))
         (full-url (concat (string-remove-suffix "/" base-url) "/" endpoint))
         (buf (url-retrieve-synchronously full-url t t 10)))
    (unless buf
      (user-error "𝖥𝖫∀𝖬∫: request to %s failed" full-url))
    (unwind-protect
        (with-current-buffer buf
          ;; Use url-http's own header/body boundary marker rather
          ;; than searching for a literal "\n\n" -- a real HTTP
          ;; response uses CRLF line endings, so "\r\n\r\n" has no
          ;; adjacent LF-LF pair for a plain "\n\n" search to find;
          ;; url-http-end-of-headers is set by url-http.el itself,
          ;; from actually parsing the response, so it's correct
          ;; regardless of the exact line-ending bytes used.
          (unless (and (boundp 'url-http-end-of-headers) url-http-end-of-headers)
            (user-error "𝖥𝖫∀𝖬∫: malformed HTTP response from %s" full-url))
          (goto-char url-http-end-of-headers)
          (json-parse-string (buffer-substring (point) (point-max))
                              :object-type 'alist
                              :array-type 'list))
      (kill-buffer buf))))

(defvar stex--mathhub-settings-cache nil
  "Alist of (BASE-URL . MATHHUBS-LIST); memoizes `stex--mathhub-settings'.")

(defun stex--mathhub-settings ()
  "Return the connected server's configured MathHub directories."
  (let ((base (stex--mathhub-base-url)))
    (or (cdr (assoc base stex--mathhub-settings-cache))
        (let* ((resp (stex--http-post base "api/settings" nil))
               (mathhubs (alist-get 'mathhubs (car resp))))
          (push (cons base mathhubs) stex--mathhub-settings-cache)
          mathhubs))))

(defun stex--mathhub-group-entries (&optional group-id)
  "Return (GROUP-IDS . ARCHIVE-IDS) under GROUP-ID (top-level if nil)."
  (let* ((base (stex--mathhub-base-url))
         (resp (stex--http-post base "api/backend/group_entries"
                                 (when group-id `(("in" . ,group-id)))))
         (groups (mapcar (lambda (g) (alist-get 'id g)) (nth 0 resp)))
         (archives (mapcar (lambda (a) (alist-get 'id a)) (nth 1 resp))))
    (cons groups archives)))

(defun stex--mathhub-archive-entries (archive-id &optional path)
  "Return (DIR-REL-PATHS . FILE-REL-PATHS) in ARCHIVE-ID at PATH."
  (let* ((base (stex--mathhub-base-url))
         (resp (stex--http-post base "api/backend/archive_entries"
                                 `(("archive" . ,archive-id)
                                   ("path" . ,path))))
         (dirs (mapcar (lambda (d) (alist-get 'rel_path d)) (nth 0 resp)))
         (files (mapcar (lambda (f) (alist-get 'rel_path f)) (nth 1 resp))))
    (cons dirs files)))

(defun stex--mathhub-basename (id)
  "Return the last /-separated segment of ID."
  (car (last (split-string id "/" t))))

(defun stex--drill-down (prompt root children-fn label-fn)
  "Interactively descend a tree via `completing-read', prompting PROMPT.
Start at ROOT.  CHILDREN-FN is called with the current node and must
return (CONTAINERS . LEAVES), each a list of opaque nodes.  LABEL-FN
formats a node as a string for display.  Returns the chosen leaf
node.

Candidate labels are basenames, so two sibling containers/leaves that
happen to share one are ambiguous; not disambiguated in this version."
  (let ((stack (list root)))
    (catch 'stex-leaf
      (while t
        (let* ((node (car stack))
               (children (funcall children-fn node))
               (containers (car children))
               (leaves (cdr children)))
          (if (and (null containers) (null leaves))
              (if (cdr stack)
                  (progn (message "𝖥𝖫∀𝖬∫: no entries here") (pop stack))
                (user-error "𝖥𝖫∀𝖬∫: no MathHub entries found"))
            (let* ((container-labels
                    (mapcar (lambda (c) (concat (funcall label-fn c) "/"))
                            containers))
                   (leaf-labels (mapcar label-fn leaves))
                   (candidates (append (when (cdr stack) '(".."))
                                        container-labels leaf-labels))
                   (choice (completing-read prompt candidates nil t)))
              (cond
               ((string= choice "..") (pop stack))
               ((member choice container-labels)
                (push (nth (cl-position choice container-labels :test #'string=)
                           containers)
                      stack))
               (t
                (throw 'stex-leaf
                       (nth (cl-position choice leaf-labels :test #'string=)
                            leaves)))))))))))

(defun stex--choose-archive ()
  "Interactively choose a local MathHub archive id."
  (stex--drill-down "MathHub archive: " nil
                     #'stex--mathhub-group-entries
                     #'stex--mathhub-basename))

(defun stex--choose-file (archive-id)
  "Interactively choose a file's rel_path within ARCHIVE-ID."
  (stex--drill-down (format "File in %s: " archive-id) nil
                     (lambda (rel-path)
                       (stex--mathhub-archive-entries archive-id rel-path))
                     #'stex--mathhub-basename))

(defun stex--choose-group ()
  "Interactively choose a MathHub group id.
Unlike `stex--choose-archive' (via `stex--drill-down', always
descends to a leaf), this lets you stop at any group level: once
you've descended into at least one group, a \".\" candidate lets you
select the current group instead of continuing into a subgroup.  (No
such option at the top level -- stopping there would just mean \"the
whole MathHub\", already covered by `stex-mathhub-update' with no
prefix argument.)  A group with no subgroups is returned immediately,
without prompting.  Signals `user-error' if there are no groups at
all."
  (let ((current nil))
    (catch 'chosen
      (while t
        (let ((groups (car (stex--mathhub-group-entries current))))
          (when (and (null groups) (null current))
            (user-error "𝖥𝖫∀𝖬∫: no MathHub groups found"))
          (when (null groups)
            (throw 'chosen current))
          (let* ((here ".")
                 (candidates (append (mapcar #'stex--mathhub-basename groups)
                                      (when current (list here))))
                 (choice (completing-read
                          (format "MathHub group%s (%s = use this group): "
                                  (if current (concat " [" current "]") "")
                                  here)
                          candidates nil t)))
            (if (equal choice here)
                (throw 'chosen current)
              (setq current
                    (nth (cl-position choice groups
                                       :key #'stex--mathhub-basename :test #'string=)
                         groups)))))))))

(defun stex--mathhub-resolve-dir (id)
  "Resolve mathhub ID (an archive or group id) to its local directory.
Looks for ID under each of `stex--mathhub-settings' in turn, the same
convention `mathhub.ts' uses: <mathhub>/<id segments>.  Works equally
for archive ids and group ids -- both are just directories in that
same layout, an archive's just additionally a git repo with a
`source' subdirectory.  Signals `user-error' if ID isn't found under
any configured MathHub directory."
  (let ((segments (split-string id "/" t)))
    (or (seq-some
         (lambda (mh)
           (let ((root (apply #'file-name-concat mh segments)))
             (when (file-directory-p root) root)))
         (stex--mathhub-settings))
        (user-error
         "𝖥𝖫∀𝖬∫: could not find %s locally under any configured MathHub directory"
         id))))

(defun stex--mathhub-local-path (archive-id rel-path)
  "Resolve ARCHIVE-ID/REL-PATH to a local file, or signal `user-error'."
  (apply #'file-name-concat (stex--mathhub-resolve-dir archive-id)
         "source" (split-string rel-path "/" t)))

;;;###autoload
(defun stex-mathhub-open-file ()
  "Browse local MathHub archives and open the chosen file."
  (interactive)
  (let* ((archive (stex--choose-archive))
         (rel-path (stex--choose-file archive))
         (path (stex--mathhub-local-path archive rel-path)))
    (find-file path)))

(defun stex--insert-usemodule (buffer archive module-path)
  "In BUFFER, insert a \\usemodule reference to ARCHIVE's MODULE-PATH.
Port of `insertUsemodule' in vscode/src/ts/utils.ts: insert after
\\begin{document}, skipping blank lines and existing
\\usemodule/\\importmodule lines; if there is no \\begin{document} at
all, insert at the very top of the buffer (matching that function's
actual fallback behavior)."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "\\\\begin{document}" nil t)
        (forward-line 1)
        (while (and (not (eobp))
                    (save-excursion
                      (beginning-of-line)
                      (looking-at-p
                       "[ \t]*\\(?:$\\|\\\\\\(?:use\\|import\\)module\\)")))
          (forward-line 1)))
      (insert (format "\\usemodule[%s]{%s}\n" archive module-path)))))

;;;###autoload
(defun stex-mathhub-insert-usemodule ()
  "Browse local MathHub archives and insert a \\usemodule reference.
Inserts a reference to the chosen file at point in the buffer this
command was called from."
  (interactive)
  (let* ((buffer (current-buffer))
         (archive (stex--choose-archive))
         (rel-path (stex--choose-file archive))
         (module-path (string-remove-suffix ".tex" rel-path)))
    (stex--insert-usemodule buffer archive module-path)))

;;; Fuzzy symbol search

;; The VS Code extension's "fuzzy module search" is a webview iframe
;; onto `flams''s own web UI at `<server-url>/vscode/search' -- not
;; something to embed here (no in-Emacs browser). But that page turns
;; out to be a thin frontend over a real, plain HTTP endpoint,
;; `POST api/search_symbols' (a Leptos `#[server(prefix = "/api",
;; endpoint = "search_symbols")]' function, source/router/search/src/lib.rs
;; in the FLAMS repository -- same mechanism, and callable the same
;; way over `stex--http-post', as `api/backend/group_entries' &c.
;; already in use above), taking `query'/`num_results' and returning
;; `(score, SymbolUri, DocumentElementUri)' triples ranked by FLAMS's
;; own full-text/fuzzy index across the whole MathHub -- not just this
;; buffer's declarations, unlike `stex--known-symbol-names'.
;; `SymbolUri' serializes as its URI string, of the form
;; `<base>?a=<archive>&p=<path>&m=<module>&s=<symbol>' (`p=' absent
;; when the module's file and name coincide) -- see FLAMS's
;; `ftml_uris' crate for the exact `Display' impls this mirrors.
;;
;; `stex-mathhub-search-symbols' turns that into real incremental
;; fuzzy search in the minibuffer via `completion-table-dynamic'
;; (re-querying FLAMS on every keystroke, same as any other search-
;; backed `completing-read'), then inserts a \usemodule for whichever
;; symbol's module you pick -- the same end result as the VS Code
;; webview's search-then-click flow, just without an embedded browser
;; in between.

(defun stex--symbol-uri-component (key uri)
  "Extract query-component KEY (e.g. \"a\", \"p\", \"m\", \"s\") from URI.
URI is a flams symbol/module URI string of the form
\"<base>?a=<archive>&p=<path>&m=<module>&s=<symbol>\" (\"p=\" is
optional).  Return nil if KEY isn't present."
  (when (string-match (concat "[?&]" (regexp-quote key) "=\\([^&]*\\)") uri)
    (match-string 1 uri)))

(defun stex--symbol-uri-usemodule-arg (uri)
  "Return (ARCHIVE . MODULE-PATH) for `stex--insert-usemodule', from URI.
MODULE-PATH is \"path?module\" when URI has a \"p=\" component (the
file the module lives in differs from the module's own name), or just
the module name when it doesn't -- mirroring how `\\usemodule' itself
is written in both cases (STEX manual, section 7.1)."
  (let ((archive (stex--symbol-uri-component "a" uri))
        (path (stex--symbol-uri-component "p" uri))
        (module (stex--symbol-uri-component "m" uri)))
    (cons archive (if path (concat path "?" module) module))))

(defun stex--symbol-uri-label (uri)
  "Human-readable completion label for URI, for `stex-mathhub-search-symbols'."
  (let ((archive (stex--symbol-uri-component "a" uri))
        (symbol (stex--symbol-uri-component "s" uri))
        (arg (cdr (stex--symbol-uri-usemodule-arg uri))))
    (format "%s  --  %s[%s]" (or symbol "?") archive arg)))

(defvar stex--search-symbols-last-results nil
  "Alist of (LABEL . SYMBOL-URI-STRING) from the last search.
Refreshed by `stex--search-symbols-collection'; read by
`stex-mathhub-search-symbols' to recover the full URI for the label
`completing-read' returns, since the label alone doesn't carry the
archive/path/module apart again.")

(defun stex--search-symbols-collection (base query)
  "Query BASE's flams server for QUERY, return a list of labels.
Also refreshes `stex--search-symbols-last-results'.  Meant to be
wrapped in `completion-table-dynamic' -- see
`stex-mathhub-search-symbols'.  Returns nil (rather than erroring, and
without querying at all) for a QUERY under 2 characters, to avoid
firing a request on every single keystroke of a fresh search."
  (if (< (length query) 2)
      nil
    (let ((results (ignore-errors
                      (stex--http-post base "api/search_symbols"
                                        `(("query" . ,query)
                                          ("num_results" . "30"))))))
      (setq stex--search-symbols-last-results
            (mapcar (lambda (r)
                      (let ((uri (nth 1 r)))
                        (cons (stex--symbol-uri-label uri) uri)))
                    results))
      (mapcar #'car stex--search-symbols-last-results))))

;;;###autoload
(defun stex-mathhub-search-symbols ()
  "Fuzzy-search FLAMS's indexed symbols and insert a \\usemodule for one.
Queries `api/search_symbols' anew on every keystroke (see
`stex--search-symbols-collection'), ranked by FLAMS's own full-text
index across the whole MathHub -- not limited to this buffer or its
\\usemodule'd files, unlike the local completion `stex-mode' offers at
`\\symref' &c.'s own symbol argument.  Each keystroke blocks briefly on
an HTTP round-trip, same as every other MathHub-browsing command in
this package; works with no `.tex' file open, same as those too (see
`stex--mathhub-base-url')."
  (interactive)
  (let* ((target-buffer (current-buffer))
         (base (stex--mathhub-base-url))
         (label (completing-read
                 "Search symbols (2+ chars): "
                 (completion-table-dynamic
                  (lambda (q) (stex--search-symbols-collection base q)))))
         (uri (cdr (assoc label stex--search-symbols-last-results))))
    (unless uri
      (user-error "𝖥𝖫∀𝖬∫: no matching symbol chosen"))
    (let ((arg (stex--symbol-uri-usemodule-arg uri)))
      (stex--insert-usemodule target-buffer (car arg) (cdr arg)))))

;;; Category-filtered content search

;; VS Code's search webview (see "Fuzzy symbol search" above) also
;; exposes checkboxes to restrict results to specific categories --
;; Documents, Paragraphs, Definitions, Examples, Assertions, Problems
;; -- backed by a second, richer Leptos server function alongside
;; `search_symbols', `POST api/search' (same
;; source/router/search/src/lib.rs, same wire mechanism). Its `opts'
;; parameter is a `FragmentQueryFilter' struct
;; (backend-types/src/search.rs); empirically confirmed -- by running
;; a real `flams' instance directly and probing five encoding
;; hypotheses -- that Leptos's default `serde_qs' form encoding wants
;; *bracket* notation for nested-struct fields, `opts[flags]=<bitmask>',
;; not `opts.flags=', not a JSON blob under `opts', and not `flags'
;; flattened to the top level; the latter three all come back as a 500
;; "missing field 'opts'" (or a QsDeserializer parse error for the
;; JSON-blob case), since `FragmentQueryFilter''s own fields are all
;; `#[serde(default)]' but `opts' itself is not optional.
;; `in_documents'/`languages' are left unset (default to "no
;; restriction") -- only `flags' is ever sent.
;;
;; The response is `Vec<(f32, SearchResult)>'; `SearchResult' is a
;; plain (externally-tagged, the serde default) enum --
;; `Document(DocumentUri)' or `Paragraph { uri: DocumentElementUri,
;; fors: Vec<SymbolUri>, def_like: bool, kind: SearchResultKind }' --
;; so each JSON result is either `{"Document": "<uri>"}' or
;; `{"Paragraph": {"uri": ..., "fors": [...], "def_like": ..., "kind":
;; "..."}}'. `DocumentUri'/`DocumentElementUri' serialize as their URI
;; strings the same way `SymbolUri' does (`serde_with::SerializeDisplay'
;; on all three, confirmed by reading ftml_uris's uris/document.rs and
;; uris/doc_element.rs), of the form
;; `<base>?a=<archive>&p=<path>&d=<name>&l=<language>[&e=<element>]'
;; (their `Display' impls) -- reusing `stex--symbol-uri-component' to
;; pick that apart works unchanged for these too, since it's keyed
;; generically by component letter, not specific to `SymbolUri'.
;;
;; Picking a result opens the underlying file -- there's no natural
;; \usemodule target here, unlike the symbol search (a Paragraph
;; result is a spot *within* a document, not a module to import) --
;; jumping to the matched element's own position isn't attempted, same
;; fidelity as `stex-mathhub-open-file'.

(defconst stex--search-category-flags
  '(("Documents" . 1) ("Paragraphs" . 2) ("Definitions" . 4)
    ("Examples" . 8) ("Assertions" . 16) ("Problems" . 32))
  "Category name -> `QueryFilterFlags' bit value (backend-types/src/search.rs).
Mirrors the VS Code search webview's filter checkboxes.")

(defconst stex--search-all-categories-flags 127
  "Bitmask meaning \"no category filter\".
Sent when no category is chosen.  `QueryFilterFlags::new()''s own
default (0b0111_1111 = 127), used verbatim rather than OR-ing together
every value in `stex--search-category-flags' ourselves, in case of an
unnamed/reserved high bit.")

(defun stex--search-result-doc-summary (uri)
  "\"ARCHIVE[PATH/NAME]\"-style summary of a DocumentUri/DocumentElementUri URI."
  (let ((archive (stex--symbol-uri-component "a" uri))
        (path (stex--symbol-uri-component "p" uri))
        (name (stex--symbol-uri-component "d" uri)))
    (format "%s[%s]" archive (if path (concat path "/" name) name))))

(defun stex--search-result-uri (entry)
  "The DocumentUri/DocumentElementUri string ENTRY resolves to.
ENTRY is a raw `SearchResult' alist -- see the Commentary above
`stex--search-category-flags'."
  (or (alist-get 'Document entry)
      (alist-get 'uri (alist-get 'Paragraph entry))))

(defun stex--search-result-label (entry)
  "Human-readable completion label for a raw `SearchResult' alist ENTRY."
  (let ((doc (alist-get 'Document entry))
        (para (alist-get 'Paragraph entry)))
    (if doc
        (format "[Document]  %s" (stex--search-result-doc-summary doc))
      (let* ((kind (alist-get 'kind para))
             (fors (alist-get 'fors para))
             (sym (and fors (stex--symbol-uri-component "s" (car fors)))))
        (format "[%s]  %s -- %s" kind (or sym "?")
                (stex--search-result-doc-summary (alist-get 'uri para)))))))

(defun stex--search-result-local-path (uri)
  "Resolve a DocumentUri/DocumentElementUri string URI to a local file.
Tries the language-suffixed filename first, then the bare \".tex\"
name (STEX's own file-naming convention -- mirrors
`stex--resolve-local-usemodule-files')."
  (let* ((archive (stex--symbol-uri-component "a" uri))
         (path (stex--symbol-uri-component "p" uri))
         (name (stex--symbol-uri-component "d" uri))
         (lang (stex--symbol-uri-component "l" uri))
         (rel (concat (if path (concat path "/") "") name))
         (lang-path (stex--mathhub-local-path archive (concat rel "." lang ".tex")))
         (plain-path (stex--mathhub-local-path archive (concat rel ".tex"))))
    (if (file-exists-p lang-path) lang-path plain-path)))

(defvar stex--search-last-results nil
  "Alist of (LABEL . RAW-RESULT-ENTRY) from the last `stex-mathhub-search' query.
Refreshed by `stex--search-collection'; read by `stex-mathhub-search'
to recover the full result for the label `completing-read' returns.")

(defun stex--search-collection (base query flags)
  "Query BASE's flams server for QUERY restricted by FLAGS, return labels.
Also refreshes `stex--search-last-results'.  Meant to be wrapped in
`completion-table-dynamic' -- see `stex-mathhub-search'.  Returns nil
for a QUERY under 2 characters, same reasoning as
`stex--search-symbols-collection'."
  (if (< (length query) 2)
      nil
    (let ((results (ignore-errors
                      (stex--http-post base "api/search"
                                        `(("query" . ,query)
                                          ("num_results" . "30")
                                          ("opts[flags]" . ,(number-to-string flags)))))))
      (setq stex--search-last-results
            (mapcar (lambda (r)
                      (let ((entry (nth 1 r)))
                        (cons (stex--search-result-label entry) entry)))
                    results))
      (mapcar #'car stex--search-last-results))))

;;;###autoload
(defun stex-mathhub-search ()
  "Fuzzy-search FLAMS's indexed content, filtered by category, open the result.
Prompts for zero or more categories (`stex--search-category-flags';
empty selection means every category, see
`stex--search-all-categories-flags'), then searches `api/search'
incrementally as you type -- same `completion-table-dynamic' pattern
as `stex-mathhub-search-symbols', just against the richer
content-search endpoint instead of the symbol-only one -- and opens
the chosen result's file.  Works with no `.tex' file open, same as
the other MathHub commands (see `stex--mathhub-base-url')."
  (interactive)
  (let* ((base (stex--mathhub-base-url))
         (categories (completing-read-multiple
                      "Categories (empty = all, TAB to complete): "
                      (mapcar #'car stex--search-category-flags)))
         (chosen-flags (delq nil (mapcar (lambda (c)
                                            (cdr (assoc c stex--search-category-flags)))
                                          categories)))
         (flags (if chosen-flags
                    (apply #'logior chosen-flags)
                  stex--search-all-categories-flags))
         (label (completing-read
                 "Search (2+ chars): "
                 (completion-table-dynamic
                  (lambda (q) (stex--search-collection base q flags)))))
         (entry (cdr (assoc label stex--search-last-results))))
    (unless entry
      (user-error "𝖥𝖫∀𝖬∫: no matching result chosen"))
    (find-file (stex--search-result-local-path (stex--search-result-uri entry)))))

;;;###autoload
(defun stex-mathhub-new-archive ()
  "Create a new MathHub archive.
Prompts for an archive id (e.g. \"My/Archive/Name\") and a URL base
\(where you plan to host it), then sends flams/newArchive -- a direct
port of `new_archive' in vscode/src/ts/commands.ts, including its
default URL base.  Works with no `.tex' file open, same as the other
MathHub commands: launches a standalone connection via
`stex-mathhub-root' if nothing is connected yet."
  (interactive)
  (let ((server (stex--ensure-mathhub-server)))
    (let ((archive (string-trim
                     (read-string "New MathHub archive (e.g. My/Archive/Name): ")))
          (urlbase (string-trim
                    (read-string "Archive URL base: " "http://mathhub.info"))))
      (when (string-empty-p archive)
        (user-error "𝖥𝖫∀𝖬∫: archive name can't be empty"))
      (jsonrpc-notify server "flams/newArchive"
                       (list :archive archive :urlbase urlbase))
      (message "𝖥𝖫∀𝖬∫: requested new archive %s" archive))))

;;; MathHub tree view

;; Unlike `stex-mathhub-open-file'/`stex-mathhub-insert-usemodule' (a
;; one-shot `completing-read' drill-down), `stex-mathhub-tree' shows
;; the whole local MathHub as a persistent, incrementally-expandable
;; tree, built with `tree-widget' -- the same library eglot's own
;; `eglot-show-call-hierarchy' uses, just for the whole archive
;; collection instead of one file's call graph.
;;
;; Each node is a plist: (:kind group :id ID), (:kind archive :id ID),
;; (:kind dir :archive ID :path REL-PATH), or
;; (:kind file :archive ID :path REL-PATH).  Children are only fetched
;; (over HTTP, via the same functions the drill-down commands use)
;; when a node is actually expanded.

(defun stex--mathhub-node-children (node)
  "Return (CONTAINER-NODES . LEAF-NODES) that NODE expands to."
  (pcase (plist-get node :kind)
    ('group
     (let ((entries (stex--mathhub-group-entries (plist-get node :id))))
       (cons (mapcar (lambda (g) (list :kind 'group :id g)) (car entries))
             (mapcar (lambda (a) (list :kind 'archive :id a)) (cdr entries)))))
    ('archive
     (let ((entries (stex--mathhub-archive-entries (plist-get node :id))))
       (cons (mapcar (lambda (d) (list :kind 'dir :archive (plist-get node :id) :path d))
                      (car entries))
             (mapcar (lambda (f) (list :kind 'file :archive (plist-get node :id) :path f))
                      (cdr entries)))))
    ('dir
     (let ((entries (stex--mathhub-archive-entries (plist-get node :archive)
                                                     (plist-get node :path))))
       (cons (mapcar (lambda (d) (list :kind 'dir :archive (plist-get node :archive) :path d))
                      (car entries))
             (mapcar (lambda (f) (list :kind 'file :archive (plist-get node :archive) :path f))
                      (cdr entries)))))
    ('file (cons nil nil))))

(defun stex--mathhub-node-label (node)
  "Return NODE's display label (its id/path's last path segment)."
  (stex--mathhub-basename
   (pcase (plist-get node :kind)
     ((or 'group 'archive) (plist-get node :id))
     ((or 'dir 'file) (plist-get node :path)))))

(define-button-type 'stex--mathhub-tree-item
  'follow-link t
  'face 'font-lock-function-name-face)

(defun stex--mathhub-tree-file-button-action (button)
  "Open the file associated with BUTTON, a MathHub tree file tag.
A named top-level function, not a closure -- see
`stex--git-pull-sentinel' for why that matters in this file; reads
the node off BUTTON via `button-get' (which works for a text button
like this one given its buffer position, same as for an overlay
button) instead of closing over it."
  (let ((node (button-get button 'stex--mathhub-node)))
    (find-file (stex--mathhub-local-path (plist-get node :archive)
                                          (plist-get node :path)))))

(defun stex--mathhub-tree-tag (node)
  "Build the tag string for NODE in the MathHub tree.
File nodes are buttons that open the file; group/archive/dir nodes
are plain text -- expand/collapse them via `tree-widget's own
icon/keys, same as any other tree-widget node.  Every kind of tag
carries a `stex--mathhub-node' text property either way, so commands
like `stex-mathhub-tree-narrow' can tell what's on the current line
regardless of node kind."
  (let ((label (stex--mathhub-node-label node)))
    (if (eq (plist-get node :kind) 'file)
        (with-temp-buffer
          (insert-text-button
           label
           :type 'stex--mathhub-tree-item
           'stex--mathhub-node node
           'help-echo "mouse-1, RET: open file"
           'action #'stex--mathhub-tree-file-button-action)
          (buffer-string))
      (propertize label 'stex--mathhub-node node))))

(defvar-local stex--mathhub-tree-roots nil
  "Root nodes of the current `stex-mathhub-tree-mode' buffer.")

(defvar-local stex--mathhub-tree-history nil
  "Stack of previous `stex--mathhub-tree-roots' values.
Pushed to by `stex-mathhub-tree-narrow', popped by
`stex-mathhub-tree-up'.")

(defun stex--mathhub-tree-node-at-point ()
  "Return the MathHub node for the current line, or nil.
Looks anywhere on the line, not just exactly on the tag text --
forgiving the way `dired' is about where on a line you press a key."
  (let ((pos (text-property-not-all (line-beginning-position) (line-end-position)
                                     'stex--mathhub-node nil)))
    (and pos (get-char-property pos 'stex--mathhub-node))))

(defun stex--mathhub-tree-header ()
  "Build the header-line text describing the current tree scope."
  (concat "𝖥𝖫∀𝖬∫ MathHub — "
          (if stex--mathhub-tree-history
              (format "%s  [%s]"
                      (stex--mathhub-node-label (car stex--mathhub-tree-roots))
                      (plist-get (car stex--mathhub-tree-roots) :kind))
            "whole tree")))

(defun stex--mathhub-tree-expand (node _widget)
  "Return the list of child tree-widgets for NODE.
A named top-level function, not a closure -- see
`stex--git-pull-sentinel' for why that matters in this file; NODE is
bound into each widget's `:expander' via `apply-partially' (see
`stex--mathhub-tree-widget'), which is safe regardless of this file's
`lexical-binding' state since `apply-partially' itself is defined in
Emacs's own (always lexically-bound) subr.el, rather than by a lambda
literal here closing over NODE directly."
  (let ((children (stex--mathhub-node-children node)))
    (append (mapcar #'stex--mathhub-tree-widget (car children))
            (mapcar #'stex--mathhub-tree-widget (cdr children)))))

(defun stex--mathhub-tree-widget (node)
  "Build a (not yet inserted) `tree-widget' spec for NODE.
Children are fetched lazily: NODE's `:expander' only calls
`stex--mathhub-node-children' (an HTTP request) when the widget is
actually expanded, and converts each child node the same way,
recursively."
  (let ((w (widget-convert
            'tree-widget
            :tag (stex--mathhub-tree-tag node)
            :expander (apply-partially #'stex--mathhub-tree-expand node))))
    (widget-put w :empty-icon (widget-get w :leaf-icon))
    w))

(defun stex--mathhub-tree-render ()
  "(Re)populate the current MathHub tree buffer from its root nodes."
  (let ((inhibit-read-only t)
        (line (line-number-at-pos)))
    (erase-buffer)
    (mapc (lambda (root) (widget-create (stex--mathhub-tree-widget root)))
          stex--mathhub-tree-roots)
    (setq header-line-format (stex--mathhub-tree-header))
    (goto-char (point-min))
    (forward-line (1- line))))

(defun stex-mathhub-tree-narrow ()
  "Narrow the MathHub tree to the group/archive on the current line."
  (interactive)
  (let ((node (stex--mathhub-tree-node-at-point)))
    (unless (and node (memq (plist-get node :kind) '(group archive)))
      (user-error "𝖥𝖫∀𝖬∫: point at a group or archive to narrow to it"))
    (push stex--mathhub-tree-roots stex--mathhub-tree-history)
    (setq stex--mathhub-tree-roots (list node))
    (stex--mathhub-tree-render)))

(defun stex-mathhub-tree-up ()
  "Undo the last `stex-mathhub-tree-narrow', restoring the wider view."
  (interactive)
  (unless stex--mathhub-tree-history
    (user-error "𝖥𝖫∀𝖬∫: already showing the widest view"))
  (setq stex--mathhub-tree-roots (pop stex--mathhub-tree-history))
  (stex--mathhub-tree-render))

(defun stex-mathhub-tree-open ()
  "Open the file on the current line, if there is one."
  (interactive)
  (let ((node (stex--mathhub-tree-node-at-point)))
    (unless (and node (eq (plist-get node :kind) 'file))
      (user-error "𝖥𝖫∀𝖬∫: no file on this line"))
    (find-file (stex--mathhub-local-path (plist-get node :archive)
                                          (plist-get node :path)))))

(defun stex--mathhub-tree-target-buffer ()
  "Return the buffer a MathHub tree action should act on.
The most-recently-used window's buffer, excluding the tree's own
window -- the usual trick for sidebar-style buffers, since the tree
buffer itself is obviously never a sensible target."
  (let ((win (get-mru-window nil nil 'not-selected)))
    (if win (window-buffer win)
      (user-error "𝖥𝖫∀𝖬∫: no other window to insert into"))))

(defun stex-mathhub-tree-insert-usemodule ()
  "Insert a \\usemodule reference for the file on the current line.
Inserts into the most-recently-used other window's buffer -- see
`stex--mathhub-tree-target-buffer'."
  (interactive)
  (let ((node (stex--mathhub-tree-node-at-point)))
    (unless (and node (eq (plist-get node :kind) 'file))
      (user-error "𝖥𝖫∀𝖬∫: no file on this line"))
    (stex--insert-usemodule (stex--mathhub-tree-target-buffer)
                             (plist-get node :archive)
                             (string-remove-suffix ".tex" (plist-get node :path)))))

(defun stex-mathhub-tree-update-at-point ()
  "Git-pull the archive or group on the current line.
A directory/file line updates its containing archive.  Unlike
`stex-mathhub-update-archive'/`stex-mathhub-update-group', doesn't
re-prompt for what to update -- you're already looking at it."
  (interactive)
  (let ((node (stex--mathhub-tree-node-at-point)))
    (unless node
      (user-error
       "𝖥𝖫∀𝖬∫: point at a group, archive, directory, or file to update its archive"))
    (pcase (plist-get node :kind)
      ((or 'archive 'group)
       (let ((id (plist-get node :id)))
         (stex--mathhub-update-roots
          (list (stex--mathhub-resolve-dir id))
          (format "%s %s" (plist-get node :kind) id))))
      ((or 'dir 'file)
       (let ((archive (plist-get node :archive)))
         (stex--mathhub-update-roots
          (list (stex--mathhub-resolve-dir archive))
          (format "archive %s" archive)))))))

(define-derived-mode stex-mathhub-tree-mode special-mode "sTeX-MathHub"
  "Major mode for browsing local MathHub archives as a tree.
\\{stex-mathhub-tree-mode-map}"
  (setq buffer-read-only t))

(define-key stex-mathhub-tree-mode-map "n" #'stex-mathhub-tree-narrow)
(define-key stex-mathhub-tree-mode-map "^" #'stex-mathhub-tree-up)
(define-key stex-mathhub-tree-mode-map "o" #'stex-mathhub-tree-open)
(define-key stex-mathhub-tree-mode-map "u" #'stex-mathhub-tree-insert-usemodule)
(define-key stex-mathhub-tree-mode-map "a" #'stex-mathhub-new-archive)
(define-key stex-mathhub-tree-mode-map "U" #'stex-mathhub-update)
(define-key stex-mathhub-tree-mode-map "p" #'stex-mathhub-tree-update-at-point)

;;;###autoload
(defun stex-mathhub-tree ()
  "Show the local MathHub archive collection as a navigable tree.
Unlike `stex-mathhub-open-file'/`stex-mathhub-insert-usemodule' (a
one-shot drill-down), this opens a persistent buffer showing the
whole MathHub at once, reconfigurable in place:
  n  `stex-mathhub-tree-narrow' -- narrow to the group/archive at point
  ^  `stex-mathhub-tree-up' -- undo the last narrow
  o  `stex-mathhub-tree-open' -- open the file on the current line
  u  `stex-mathhub-tree-insert-usemodule' -- \\usemodule for it, in
     whatever window you were last in
  a  `stex-mathhub-new-archive' -- create a new archive; the tree
     refreshes itself once flams confirms it (flams/updateMathHub)
  U  `stex-mathhub-update' -- git-pull every local archive
  p  `stex-mathhub-tree-update-at-point' -- git-pull just the
     archive/group on the current line
  g  `revert-buffer' -- full reset to the whole MathHub
Also works with no `.tex' file open at all, launching a standalone
`flams' connection via `stex-mathhub-root' if nothing is already
connected -- see `stex--ensure-mathhub-server'.  Placement is
configured by `stex-mathhub-tree-side'/`stex-mathhub-tree-width'."
  (interactive)
  (let* ((entries (stex--mathhub-group-entries nil))
         (roots (append (mapcar (lambda (g) (list :kind 'group :id g)) (car entries))
                         (mapcar (lambda (a) (list :kind 'archive :id a)) (cdr entries))))
         (buf (get-buffer-create "*sTeX MathHub*")))
    (with-current-buffer buf
      (stex-mathhub-tree-mode)
      (setq-local stex--mathhub-tree-roots roots)
      (setq-local stex--mathhub-tree-history nil)
      (setq-local revert-buffer-function (lambda (&rest _) (stex-mathhub-tree)))
      (stex--mathhub-tree-render))
    (if stex-mathhub-tree-side
        (let ((display-buffer-alist
               (cons `(,(regexp-quote (buffer-name buf))
                       (display-buffer-in-side-window)
                       (side . ,stex-mathhub-tree-side)
                       (window-width . ,stex-mathhub-tree-width)
                       (slot . 0))
                     display-buffer-alist)))
          (pop-to-buffer buf))
      (pop-to-buffer buf))))

;;; MathHub git update

;; `stex-mathhub-update' git-pulls every local archive.  There is no
;; flams/vscode equivalent to port -- confirmed by grepping the
;; vscode extension for every flams/* LSP method and api/* HTTP
;; endpoint it uses; none of them do this (`flams/install' is for
;; pulling a *remote* archive you don't have yet, `flams/reload' just
;; re-scans what's already on disk).  This is a from-scratch Elisp
;; port of a plain "recursively `git pull --ff-only' every repo under
;; a directory" script, extended with the one thing that script
;; doesn't do: detect archives that would need a password/passphrase
;; to pull and skip them instead of hanging or failing the whole run.

(defconst stex--git-auth-failure-patterns
  '("terminal prompts disabled"
    "could not read Username"
    "could not read Password"
    "Permission denied (publickey"
    "Authentication failed"
    "Could not read from remote repository"
    "Host key verification failed")
  "Substrings in `git pull' output indicating a credential failure.
Reachable only because `stex--git-pull-process-environment' makes
git/ssh fail fast on a would-be prompt instead of hanging, so any of
these mean \"this archive needs a password we don't have\", not \"the
network is down\" or similar.")

(defun stex--git-pull-process-environment ()
  "Return `process-environment' forcing git/ssh to fail instead of prompting.
Without this, a `git pull' against an archive requiring a password
would hang Emacs waiting for terminal input that never comes."
  (append (list "GIT_TERMINAL_PROMPT=0"
                "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=10"
                "GIT_ASKPASS=true")
          process-environment))

(defun stex--git-auth-failure-p (output)
  "Return non-nil if OUTPUT matches a known git credential-failure pattern."
  (let ((case-fold-search t))
    (cl-some (lambda (pat) (string-match-p (regexp-quote pat) output))
             stex--git-auth-failure-patterns)))

(defun stex--classify-git-pull-result (exit-code output)
  "Classify a finished `git pull' given its EXIT-CODE and OUTPUT.
Returns `ok', `skipped' (needs credentials), or `failed'."
  (cond
   ((zerop exit-code) 'ok)
   ((stex--git-auth-failure-p output) 'skipped)
   (t 'failed)))

(defun stex--git-repo-dirs (roots)
  "Return the directory of every git repository found under ROOTS.
Does not recurse into a matched `.git' directory's own internals."
  (delete-dups
   (mapcan
    (lambda (root)
      (mapcar #'file-name-directory
              (directory-files-recursively
               root "\\.git$" t
               (lambda (dir) (not (string-suffix-p ".git" dir))))))
    roots)))

(defun stex--indent-lines (string)
  "Indent every line of STRING by four spaces."
  (mapconcat (lambda (line) (concat "    " line))
             (split-string (string-trim string) "\n")
             "\n"))

(defun stex--git-pull-status-line (status output)
  "Format a one-line (or, for failures, multi-line) report of STATUS.
OUTPUT is the pull's captured stdout+stderr, shown indented for
`failed' (not for `ok'/`skipped', which don't need it)."
  (pcase status
    ('ok "ok")
    ('skipped "skipped (needs credentials)")
    ('failed (concat "FAILED\n" (stex--indent-lines output)))))

(defun stex--git-pull-finish (results buffer)
  "Write a final summary of RESULTS (an alist of DIR . STATUS) to BUFFER."
  (let ((ok (cl-count 'ok results :key #'cdr))
        (skipped (cl-count 'skipped results :key #'cdr))
        (failed (cl-count 'failed results :key #'cdr)))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "\n=== Done: %d updated, %d skipped, %d failed (%s) ===\n"
                       ok skipped failed (current-time-string))))
    (message "𝖥𝖫∀𝖬∫: MathHub update finished: %d updated, %d skipped, %d failed"
             ok skipped failed)
    (when (cl-plusp ok)
      ;; Tell flams to re-scan the MathHub content we just changed on
      ;; disk -- it has no other way to know git touched anything.
      (ignore-errors
        (jsonrpc-notify (stex--ensure-mathhub-server) "flams/reload" (list))))))

(defun stex--git-pull-filter (proc chunk)
  "Accumulate PROC's output CHUNK for later classification.
A named top-level function, not a closure -- see `stex--git-pull-1'
for why that matters here."
  (process-put proc 'stex--output
               (concat (or (process-get proc 'stex--output) "") chunk)))

(defun stex--git-pull-sentinel (proc _event)
  "Handle PROC's completion by continuing the queue stashed on it.
Reads back DIR/REST/RESULTS/BUFFER via `process-get' rather than
closing over them, and a named top-level function rather than a
lambda, so this works correctly regardless of whether this file
happens to have `lexical-binding' enabled -- `make-process' sentinels
are called long after the call that created them returns, so a
lambda here would be relying on variables captured from a `let' whose
dynamic extent (under dynamic binding) has already ended by the time
it runs; empirically confirmed to fail with a `void-variable' error
before this function existed."
  (unless (process-live-p proc)
    (let* ((output (or (process-get proc 'stex--output) ""))
           (status (stex--classify-git-pull-result
                    (process-exit-status proc) output))
           (dir (process-get proc 'stex--dir))
           (rest (process-get proc 'stex--rest))
           (results (process-get proc 'stex--results))
           (buffer (process-get proc 'stex--pull-buffer)))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert (stex--git-pull-status-line status output) "\n"))
      (stex--git-pull-1 rest (cons (cons dir status) results) buffer))))

(defun stex--git-pull-1 (queue results buffer)
  "Asynchronously `git pull --ff-only' the first directory in QUEUE.
On completion, continues with the rest of QUEUE, accumulating each
result onto RESULTS, and appends a status line to BUFFER -- until
QUEUE is empty and `stex--git-pull-finish' runs."
  (if (null queue)
      (stex--git-pull-finish results buffer)
    (let ((dir (car queue))
          (rest (cdr queue)))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert (format "Pulling %s ... " dir)))
      (let* ((default-directory dir)
             (process-environment (stex--git-pull-process-environment))
             (proc (make-process
                    :name "stex-mathhub-pull"
                    :buffer nil
                    :noquery t
                    :command '("git" "pull" "--ff-only")
                    :filter #'stex--git-pull-filter
                    :sentinel #'stex--git-pull-sentinel)))
        (process-put proc 'stex--dir dir)
        (process-put proc 'stex--rest rest)
        (process-put proc 'stex--results results)
        (process-put proc 'stex--pull-buffer buffer)))))

(defconst stex--mathhub-update-buffer-name "*sTeX MathHub Update*"
  "Name of the progress buffer for `stex-mathhub-update' and friends.")

(defun stex--mathhub-update-roots (roots what)
  "Git-pull every repository found under ROOTS (a list of directories).
WHAT is a short description of the scope, used in the progress
buffer's header (e.g. \"the whole MathHub\", \"archive foo/bar\").
Shared by `stex-mathhub-update', `stex-mathhub-update-archive', and
`stex-mathhub-update-group' -- see `stex-mathhub-update' for the
skip-on-credential-failure/async/progress-buffer behavior, identical
regardless of scope."
  (let* ((dirs (stex--git-repo-dirs roots))
         (buffer (get-buffer-create stex--mathhub-update-buffer-name)))
    (unless dirs
      (user-error "𝖥𝖫∀𝖬∫: no git repositories found under %s"
                  (mapconcat #'identity roots ", ")))
    (with-current-buffer buffer
      (erase-buffer)
      (insert (format "=== sTeX MathHub update (%s) started %s ===\n\n"
                       what (current-time-string))))
    (display-buffer buffer)
    (stex--git-pull-1 dirs nil buffer)))

;;;###autoload
(defun stex-mathhub-update-archive ()
  "Git-pull a single MathHub archive that you choose."
  (interactive)
  (let ((archive (stex--choose-archive)))
    (stex--mathhub-update-roots (list (stex--mathhub-resolve-dir archive))
                                 (format "archive %s" archive))))

;;;###autoload
(defun stex-mathhub-update-group ()
  "Git-pull every archive in a MathHub group that you choose.
See `stex--choose-group' for how the group is picked."
  (interactive)
  (let ((group (stex--choose-group)))
    (stex--mathhub-update-roots (list (stex--mathhub-resolve-dir group))
                                 (format "group %s" group))))

;;;###autoload
(defun stex-mathhub-update (&optional scope)
  "Git-pull local MathHub archives, skipping ones needing credentials.
With no prefix argument (SCOPE nil), pulls every archive under every
directory `stex--mathhub-settings' reports.  With one `\\[universal-argument]', \
prompts for a
single archive instead (delegates to `stex-mathhub-update-archive').
With `\\[universal-argument] \\[universal-argument]' \
\(or any prefix numeric value >= 16), prompts for a
group instead, pulling every archive in it
\(`stex-mathhub-update-group') -- mirrors how
`stex-show-call-hierarchy' uses a prefix argument to pick a
direction.

Whichever scope, this launches a standalone connection via
`stex-mathhub-root' first if nothing is connected (like other MathHub
commands), runs `git pull --ff-only' in each repository -- one at a
time, asynchronously, so Emacs stays responsive -- and detects
archives whose pull would need a password or passphrase (by making
git/ssh fail immediately instead of prompting) to skip them rather
than hanging or failing the whole run.  Progress and a final summary
go to the buffer named by `stex--mathhub-update-buffer-name'."
  (interactive "P")
  (cond
   ((null scope)
    (stex--mathhub-update-roots (stex--mathhub-settings) "the whole MathHub"))
   ((>= (prefix-numeric-value scope) 16) (stex-mathhub-update-group))
   (t (stex-mathhub-update-archive))))

(provide 'stex-mode)

;;; stex-mode.el ends here
