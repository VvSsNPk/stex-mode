;;; stex-mode.el --- sTeX/FLAMS support via eglot -*- lexical-binding: t; -*-

;; Author: royaleinstein
;; Keywords: languages, tex
;; URL: https://github.com/KWARC/FLAMS
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

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
;; `stex-export-tex' and `stex-export-html'.
;;
;; `stex-mathhub-open-file' and `stex-mathhub-insert-usemodule' browse
;; your locally configured MathHub archives (queried live from the
;; connected `flams' server, so there is nothing to configure) and
;; either visit the chosen file or insert a \usemodule reference to it
;; at point.  Only local archives are browsed -- there is no
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
;; that.
;;
;; See `stex-mode-map' for a `C-c C-x'-prefixed binding to every
;; command above.
;;
;; Not implemented (yet): the quiz preview pane, the fuzzy
;; module-search UI, remote MathHub browsing and archive installation,
;; and the interactive flams/stex download-and-install wizard that the
;; VS Code extension offers.  Install those tools yourself and point
;; `stex-flams-executable' at the binary.

;;; Code:

(require 'eglot)
(require 'jsonrpc)
(require 'cl-lib)
(require 'seq)
(require 'url)
(require 'browse-url)

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

(defun stex--handle-html-result (base-url doc-uri)
  "Given BASE-URL, react to a flams/htmlResult notice about DOC-URI.
BASE-URL is the reporting server's HTTP base URL (nil if unknown);
DOC-URI is the document whose HTML just got (re)built.  Opens a
browser per `stex-preview-auto-open', or just messages that a
preview is ready via `stex-preview-browser'."
  (if (and base-url stex-preview-auto-open)
      (browse-url (stex--preview-url base-url doc-uri))
    (message "𝖥𝖫∀𝖬∫: HTML preview ready (M-x stex-preview-browser)")))

(cl-defmethod eglot-handle-notification
  ((server stex-eglot-server) (_method (eql flams/htmlResult)) &key url)
  "Handle SERVER's notice that it has (re)built HTML for URL.
URL identifies some document, not necessarily the current buffer's
file, since the server decides when to rebuild on its own schedule."
  (stex--handle-html-result (stex-eglot-server-http-url server) url))

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
    (define-key prefix "e" #'stex-export-tex)
    (define-key prefix "E" #'stex-export-html)
    (define-key prefix "p" #'stex-preview-browser)
    (define-key prefix "o" #'stex-mathhub-open-file)
    (define-key prefix "u" #'stex-mathhub-insert-usemodule)
    (define-key prefix "h" #'stex-show-call-hierarchy)
    (define-key prefix "i" #'imenu)
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
\\[stex-export-tex]  `stex-export-tex'
\\[stex-export-html]  `stex-export-html'
\\[stex-preview-browser]  `stex-preview-browser'
\\[stex-mathhub-open-file]  `stex-mathhub-open-file'
\\[stex-mathhub-insert-usemodule]  `stex-mathhub-insert-usemodule'
\\[stex-show-call-hierarchy]  `stex-show-call-hierarchy' (wraps eglot's
  own `eglot-show-call-hierarchy'; requires flams to advertise
  :callHierarchyProvider)
\\[imenu]  `imenu' (built into Emacs; eglot wires it to flams's
  documentSymbol support automatically, nothing to bind ourselves)")

;;;###autoload
(define-minor-mode stex-mode
  "Minor mode connecting the current buffer to the FLAMS/sTeX LSP server.

Enabling this in a `latex-mode'/`LaTeX-mode' buffer makes eglot launch
`flams --lsp' for it (ahead of any other server configured for that
mode in this buffer) and makes `stex-build-file', `stex-build-all',
`stex-export-tex' and `stex-export-html' available.  See
`stex-mode-map' for the full command list and its shared prefix."
  :lighter " sTeX"
  :keymap stex-mode-map
  (if stex-mode
      (condition-case err
          (progn
            (stex--check-setup)
            (setq-local eglot-server-programs
                        (cons stex--eglot-server-program-entry
                              eglot-server-programs))
            (eglot-ensure))
        (error
         (setq stex-mode nil)
         (signal (car err) (cdr err))))
    (kill-local-variable 'eglot-server-programs)))

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

(defun stex--buffer-uri ()
  "Return the current buffer file's LSP URI, or signal `user-error'."
  (unless buffer-file-name
    (user-error "𝖥𝖫∀𝖬∫: buffer is not visiting a file"))
  (eglot-path-to-uri buffer-file-name))

(defun stex--build-request (method)
  "Send build request METHOD (\"flams/buildOne\" or \"flams/buildAll\")."
  (let ((server (stex--current-server))
        (uri (stex--buffer-uri)))
    (jsonrpc-async-request
     server method (list :uri uri)
     :success-fn (lambda (_result)
                   (message "𝖥𝖫∀𝖬∫: build queued"))
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
     :success-fn (lambda (result)
                   (if (and (stringp result) (not (string-empty-p result)))
                       (browse-url (stex--preview-url base result))
                     (message
                      "𝖥𝖫∀𝖬∫: no preview available; building may have failed")))
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
          (goto-char (point-min))
          (unless (re-search-forward "\n\n" nil t)
            (user-error "𝖥𝖫∀𝖬∫: malformed HTTP response from %s" full-url))
          (json-parse-string (buffer-substring (point) (point-max))
                              :object-type 'alist
                              :array-type 'list))
      (kill-buffer buf))))

(defvar stex--mathhub-settings-cache nil
  "Alist of (BASE-URL . MATHHUBS-LIST); memoizes `stex--mathhub-settings'.")

(defun stex--mathhub-settings ()
  "Return the connected server's configured MathHub directories."
  (let ((base (stex--server-http-url)))
    (or (cdr (assoc base stex--mathhub-settings-cache))
        (let* ((resp (stex--http-post base "api/settings" nil))
               (mathhubs (alist-get 'mathhubs (car resp))))
          (push (cons base mathhubs) stex--mathhub-settings-cache)
          mathhubs))))

(defun stex--mathhub-group-entries (&optional group-id)
  "Return (GROUP-IDS . ARCHIVE-IDS) under GROUP-ID (top-level if nil)."
  (let* ((base (stex--server-http-url))
         (resp (stex--http-post base "api/backend/group_entries"
                                 (when group-id `(("in" . ,group-id)))))
         (groups (mapcar (lambda (g) (alist-get 'id g)) (nth 0 resp)))
         (archives (mapcar (lambda (a) (alist-get 'id a)) (nth 1 resp))))
    (cons groups archives)))

(defun stex--mathhub-archive-entries (archive-id &optional path)
  "Return (DIR-REL-PATHS . FILE-REL-PATHS) in ARCHIVE-ID at PATH."
  (let* ((base (stex--server-http-url))
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

(defun stex--mathhub-local-path (archive-id rel-path)
  "Resolve ARCHIVE-ID/REL-PATH to a local file, or signal `user-error'.
Looks for ARCHIVE-ID under each of `stex--mathhub-settings' in turn,
the same convention `mathhub.ts' uses: <mathhub>/<archive-id
segments>/source/<rel-path>."
  (let ((segments (split-string archive-id "/" t)))
    (or (seq-some
         (lambda (mh)
           (let ((root (apply #'file-name-concat mh segments)))
             (when (file-directory-p root)
               (apply #'file-name-concat root "source"
                      (split-string rel-path "/" t)))))
         (stex--mathhub-settings))
        (user-error
         "𝖥𝖫∀𝖬∫: could not find %s locally under any configured MathHub directory"
         archive-id))))

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

(provide 'stex-mode)

;;; stex-mode.el ends here
