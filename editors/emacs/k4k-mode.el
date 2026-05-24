;;; k4k-mode.el --- Major mode for k4k interaction files  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 Yann Régis-Gianas
;; SPDX-License-Identifier: MIT

;; Author:     Yann Régis-Gianas <yann@regis-gianas.org>
;; Maintainer: Yann Régis-Gianas <yann@regis-gianas.org>
;; Assisted-by: Claude:claude-opus-4-7
;; URL:        https://github.com/yurug/k4k
;; Package-Requires: ((emacs "27.1"))
;; Version:    0.1.0
;; Keywords:   tools, files

;;; Commentary:

;; A major mode for `.k4k' interaction files -- the user-facing protocol
;; surface of the k4k coding agent (see https://github.com/yurug/k4k).
;;
;; Layering
;; ========
;;
;; A `.k4k' file is markdown with a small set of k4k-managed sections
;; (`## k4k:status', `## k4k:clarification:<ts>',
;; `## k4k:tradeoff:proposal:<ts>') interleaved with user-owned ones.
;; The watcher writes the file concurrently with the user, so saves
;; MUST go through cotype (see https://github.com/yurug/cotype) to
;; avoid lost updates.
;;
;; This mode does NOT re-implement cotype save coordination -- it
;; delegates to `cotype-mode' (a minor mode shipped with cotype).
;; When `cotype-mode' is available and the file already has a
;; `.<basename>.cotype/' sidecar (k4k creates one on first run), this
;; mode turns `cotype-mode' on automatically.  Saves then route
;; through `cotype save'; the watcher's writes auto-revert into the
;; buffer.  Without cotype-mode the file still loads fine, but
;; concurrent edits race.
;;
;; What this mode adds on top
;; ==========================
;;
;; 1. Font-lock for `## k4k:*' headings (distinct face) and for
;;    `- request: <directive>' lines (the watcher's directive
;;    surface).
;; 2. Three snippet commands for the three reply patterns:
;;      M-x k4k-approve-tradeoff   inserts `Approved: Tier B|C'
;;      M-x k4k-reject-tradeoff    inserts `Rejected: <reason>'
;;      M-x k4k-request-rollback   adds `- request: rollback' to
;;                                 the status block
;; 3. Two navigation commands:
;;      M-x k4k-goto-pending-tradeoff       jump to the nearest
;;        unanswered `## k4k:tradeoff:proposal:*' block (no
;;        Approved:/Rejected: line in its body).
;;      M-x k4k-goto-pending-clarification  jump to the most
;;        recent `## k4k:clarification:*' block (highest timestamp).
;;
;; Setup
;; =====
;;
;;   (add-to-list 'load-path "~/path/to/k4k/editors/emacs")
;;   (require 'k4k-mode)
;;
;; That installs `auto-mode-alist' so files ending in `.k4k' get the
;; mode automatically.  If `markdown-mode' is on `load-path' this mode
;; derives from it (you get markdown's syntax + paragraph movement +
;; etc. for free); otherwise it falls back to `text-mode'.

;;; Code:

(require 'json)


;; -- optional dependencies: degrade gracefully ----------------------------
;;
;; `markdown-mode' and `cotype-mode' are recommended but not required.
;; We resolve them at load time so `define-derived-mode' (which needs
;; the parent's symbol at expansion time) has SOMETHING to derive from
;; even on a bare Emacs.

(eval-and-compile
  (unless (require 'markdown-mode nil 'noerror)
    ;; Fallback: derive from text-mode.  We define an alias so the
    ;; `define-derived-mode' form below typechecks against a real
    ;; mode symbol; downstream users miss markdown niceties (link
    ;; navigation, etc.) but the k4k features still work.
    (defalias 'markdown-mode 'text-mode)))

;; cotype is loaded lazily inside the hook so users without it don't
;; pay for a failed require at file-load time.  We only need its
;; entry points (cotype-maybe-enable, cotype-actor) at mode-enable
;; time.


;; -- customisation group --------------------------------------------------

(defgroup k4k nil
  "Major mode for k4k interaction files."
  :group 'tools
  :prefix "k4k-")

(defcustom k4k-actor-label "emacs:k4k"
  "Value to bind `cotype-actor' to in k4k-mode buffers.
This is the string that ends up in conflict metadata when the user
and the watcher race on the same line.  Use it to distinguish
multiple Emacs sessions if you ever run them concurrently on the
same file (e.g. \"emacs:laptop\" vs \"emacs:server\").

Only takes effect when `cotype-mode' is available."
  :type 'string :group 'k4k)

(defcustom k4k-auto-enable-cotype t
  "If non-nil, k4k-mode auto-enables `cotype-mode' when available.

The watcher writes the file concurrently with the user, so a
managed buffer NEEDS cotype's save coordination to avoid lost
updates.  Turning this off is reasonable only for read-only
browsing of k4k files outside an active watcher session."
  :type 'boolean :group 'k4k)


;; -- faces ---------------------------------------------------------------

(defface k4k-managed-heading-face
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for `## k4k:*' managed section headings.
Used to give the operator a strong read-cue that everything below
this heading is k4k's writing area, not theirs -- the user only
appends an Approved/Rejected line or fills in clarification
answers; the body otherwise belongs to the watcher."
  :group 'k4k)

(defface k4k-directive-face
  '((t :inherit font-lock-builtin-face))
  "Face for `- request: <directive>' lines in the k4k:status block.
These are the user's command channel to the watcher (rollback,
pause, …)."
  :group 'k4k)


;; -- font-lock additions -------------------------------------------------
;;
;; The patterns below stack on top of whatever markdown-mode (or
;; text-mode) already highlights.  They MUST start with `^' anchors so
;; markdown's heading regexes still win for non-k4k `##' lines.

(defconst k4k-mode-font-lock-keywords
  '(("^## k4k:\\(?:status\\|clarification\\|tradeoff[:][a-z]+\\):.*"
     0 'k4k-managed-heading-face t)
    ("^## k4k:status\\b.*"
     0 'k4k-managed-heading-face t)
    ("^[ \t]*-[ \t]+request:[ \t]+\\([a-z][a-z-]*\\)"
     1 'k4k-directive-face t))
  "Font-lock keywords added on top of the parent mode's in k4k-mode.
Each entry uses OVERRIDE=t so the k4k-managed face wins over
markdown-mode's generic heading face.")


;; -- helpers: block navigation -------------------------------------------
;;
;; A "k4k block" is the region from a `^## k4k:...' heading to (but
;; not including) the next `^## ' heading or end-of-buffer, whichever
;; comes first.  These helpers are the primitives the snippet
;; commands and the goto-pending-* commands share.

(defconst k4k--heading-rx "^## k4k:[a-z]+\\(?::[a-z]+\\)?\\(?::[^ \n]+\\)?\\s-*$"
  "Regexp matching any k4k-managed section heading line.
Matches `## k4k:status', `## k4k:clarification:<ts>',
`## k4k:tradeoff:proposal:<ts>', etc.  Anchored to whole-line so
prose accidentally containing the prefix isn't mistaken for a
heading.")

(defconst k4k--any-h2-rx "^## "
  "Regexp matching ANY level-2 heading line.
Used to find the END of a block: scan forward until the next H2 or
EOF.")

(defun k4k--current-block-bounds ()
  "Return `(START . END)' of the k4k block containing point, or nil.

START is the position of the `## k4k:…' heading line (column 0).
END is the position just BEFORE the next H2 line or
`point-max'.  Returns nil when point is not inside any k4k
block."
  (save-excursion
    (let ((start nil) (end nil))
      ;; Find heading: scan backward.  Stop on the first k4k heading
      ;; OR on any non-k4k H2 (in which case we're not inside a k4k
      ;; block).
      (beginning-of-line)
      (cond
       ((looking-at k4k--heading-rx)
        (setq start (point)))
       ((looking-at k4k--any-h2-rx)
        nil)
       (t
        (when (re-search-backward k4k--any-h2-rx nil t)
          (when (looking-at k4k--heading-rx)
            (setq start (point))))))
      (when start
        (forward-line 1)
        (setq end (if (re-search-forward k4k--any-h2-rx nil t)
                      (match-beginning 0)
                    (point-max)))
        (cons start end)))))

(defun k4k--block-body-string (bounds)
  "Return the text of the block BOUNDS (heading line excluded)."
  (save-excursion
    (goto-char (car bounds))
    (forward-line 1)
    (buffer-substring-no-properties (point) (cdr bounds))))

(defun k4k--block-has-line-p (bounds rx)
  "Non-nil if the body of block BOUNDS contains a line matching RX."
  (let ((body (k4k--block-body-string bounds)))
    (string-match-p rx body)))


;; -- helpers: insert into a block ----------------------------------------

(defun k4k--insert-at-block-end (bounds text)
  "Insert TEXT just before the end of block BOUNDS.

If the block doesn't already end with a blank line, insert one
first so the inserted text reads as a fresh paragraph.  Move point
to just after the inserted text so the user sees what they just
added."
  (save-excursion
    (goto-char (cdr bounds))
    ;; The block-end position is the start of the NEXT heading (or
    ;; point-max).  Back up over trailing whitespace so we don't push
    ;; the next heading further down with stray newlines.
    (skip-chars-backward " \t\n" (car bounds))
    (let ((insert-pos (point)))
      (goto-char insert-pos)
      (insert "\n\n" text)
      (unless (string-suffix-p "\n" text)
        (insert "\n")))))

(defun k4k--find-block-by-heading-rx (rx &optional reverse)
  "Return bounds of the first/last block whose heading matches RX.

If REVERSE is non-nil, scan from end-of-buffer backward (use this
to find the MOST RECENT timestamped block).  Returns nil when no
matching block exists."
  (save-excursion
    (goto-char (if reverse (point-max) (point-min)))
    (let ((found nil)
          (search (if reverse #'re-search-backward #'re-search-forward)))
      (when (funcall search rx nil t)
        (beginning-of-line)
        (setq found (k4k--current-block-bounds)))
      found)))


;; -- interactive commands: tradeoff replies ------------------------------

(defun k4k-approve-tradeoff (tier)
  "Approve the most recent tradeoff proposal with TIER.

TIER is `B' or `C' (Tier A is the implicit default and can't be
re-approved).  Inserts an `Approved: Tier <TIER>' line at the end
of the most recent `## k4k:tradeoff:proposal:*' block.

If the block already has an Approved/Rejected line, this signals
an error: re-approval is not a thing the watcher reads, and would
just confuse the audit trail."
  (interactive
   (list (completing-read "Approve at tier: " '("B" "C") nil t)))
  (let* ((rx "^## k4k:tradeoff:proposal:")
         (bounds (k4k--find-block-by-heading-rx rx 'reverse)))
    (unless bounds
      (user-error "No tradeoff proposal block found"))
    (when (k4k--block-has-line-p bounds "^\\(Approved\\|Rejected\\):")
      (user-error "This tradeoff already has an Approved/Rejected line"))
    (k4k--insert-at-block-end bounds
                              (format "Approved: Tier %s" tier))))

(defun k4k-reject-tradeoff (reason)
  "Reject the most recent tradeoff proposal with REASON.

REASON should be one short sentence the watcher can route into the
agent's next retry as guidance.  Inserts a `Rejected: <reason>'
line at the end of the most recent
`## k4k:tradeoff:proposal:*' block."
  (interactive "sReason for rejecting (one sentence): ")
  (when (string-empty-p (string-trim reason))
    (user-error "Rejection reason cannot be empty"))
  (let* ((rx "^## k4k:tradeoff:proposal:")
         (bounds (k4k--find-block-by-heading-rx rx 'reverse)))
    (unless bounds
      (user-error "No tradeoff proposal block found"))
    (when (k4k--block-has-line-p bounds "^\\(Approved\\|Rejected\\):")
      (user-error "This tradeoff already has an Approved/Rejected line"))
    (k4k--insert-at-block-end bounds
                              (format "Rejected: %s" reason))))


;; -- interactive commands: status-block directives -----------------------

(defun k4k--ensure-directive-in-status (directive)
  "Append `- request: DIRECTIVE' to the `## k4k:status' block.

If the directive is already present (anywhere in the body),
signal a user-error rather than duplicate it -- the watcher only
needs to see it once."
  (let ((bounds (k4k--find-block-by-heading-rx "^## k4k:status\\b")))
    (unless bounds
      (user-error "No `## k4k:status' block found"))
    (let ((rx (format "^[ \t]*-[ \t]+request:[ \t]+%s\\b"
                      (regexp-quote directive))))
      (when (k4k--block-has-line-p bounds rx)
        (user-error "`- request: %s' is already in the status block"
                    directive)))
    (k4k--insert-at-block-end bounds
                              (format "- request: %s" directive))))

(defun k4k-request-rollback ()
  "Add `- request: rollback' to the k4k:status block.
The watcher tears down the in-flight version branch on the next
poll and splices a `state: rolled-back' status update."
  (interactive)
  (k4k--ensure-directive-in-status "rollback"))

(defun k4k-request-pause ()
  "Add `- request: pause' to the k4k:status block.
The watcher idles formalize/develop until the user removes the
directive (the watcher does not auto-clear `request: pause')."
  (interactive)
  (k4k--ensure-directive-in-status "pause"))


;; -- interactive commands: navigation -----------------------------------

(defun k4k-goto-pending-tradeoff ()
  "Jump to the oldest `## k4k:tradeoff:proposal:*' block that has no
Approved/Rejected line.  Signal `user-error' when every tradeoff
has been answered (or none exists).

We pick the OLDEST pending one because tradeoffs are answered
strictly in arrival order: the watcher pauses on the first
unanswered one and won't queue further work."
  (interactive)
  (let ((found nil)
        (case-fold-search nil))
    (save-excursion
      (goto-char (point-min))
      (while (and (not found)
                  (re-search-forward "^## k4k:tradeoff:proposal:" nil t))
        (beginning-of-line)
        (let ((bounds (k4k--current-block-bounds)))
          (when (and bounds
                     (not (k4k--block-has-line-p
                           bounds
                           "^\\(Approved\\|Rejected\\):")))
            (setq found (car bounds))))
        (forward-line 1)))
    (if found
        (progn (push-mark) (goto-char found)
               (recenter 1))
      (user-error "No pending tradeoff proposal"))))

(defun k4k-goto-pending-clarification ()
  "Jump to the most recent `## k4k:clarification:*' block.

\"Pending\" for clarifications is fuzzier than for tradeoffs:
there is no machine-readable Approved/Rejected line.  The watcher
considers the user done when the spec's user-section hash
changes -- so we just jump to the newest clarification (highest
timestamp = lexicographically last)."
  (interactive)
  (let ((bounds (k4k--find-block-by-heading-rx
                 "^## k4k:clarification:" 'reverse)))
    (if bounds
        (progn (push-mark) (goto-char (car bounds))
               (recenter 1))
      (user-error "No clarification block found"))))


;; -- keymap -------------------------------------------------------------
;;
;; We hang every k4k command off the `C-c C-x' prefix to avoid
;; clobbering markdown-mode's own bindings (which heavily use
;; `C-c C-a' / `C-c C-c' / `C-c C-l' for link/style editing).
;; `C-c C-x' is markdown's "extensions" namespace, which it
;; explicitly reserves for downstream modes.

(defvar k4k-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-x a") #'k4k-approve-tradeoff)
    (define-key m (kbd "C-c C-x r") #'k4k-reject-tradeoff)
    (define-key m (kbd "C-c C-x b") #'k4k-request-rollback)
    (define-key m (kbd "C-c C-x p") #'k4k-request-pause)
    (define-key m (kbd "C-c C-x t") #'k4k-goto-pending-tradeoff)
    (define-key m (kbd "C-c C-x q") #'k4k-goto-pending-clarification)
    m)
  "Keymap for `k4k-mode'.
All bindings live under the `C-c C-x' prefix (markdown-mode's
extensions namespace) so they don't collide with markdown's own
editing commands.")


;; -- mode definition ----------------------------------------------------

;;;###autoload
(define-derived-mode k4k-mode markdown-mode "k4k"
  "Major mode for k4k interaction files (.k4k).

Adds k4k-aware font-lock, snippet commands for the three reply
patterns (Approved/Rejected/rollback), and navigation between
pending blocks.  Save coordination is delegated to `cotype-mode'
when available (see `k4k-auto-enable-cotype').

\\{k4k-mode-map}"
  ;; Stack k4k font-lock on top of markdown's.  We use APPEND=t so
  ;; markdown's own keywords run first; the OVERRIDE=t inside each
  ;; entry ensures k4k's face still wins on `## k4k:*' lines.
  (font-lock-add-keywords nil k4k-mode-font-lock-keywords 'append)
  ;; Delegate save coordination to cotype-mode if available AND the
  ;; user opted in.  We use `require ... 'noerror' to avoid a hard
  ;; dependency: a bare Emacs with no cotype installed still gets a
  ;; usable major mode (without concurrent-save protection -- but
  ;; that's an honest degradation, not a crash).
  (when (and k4k-auto-enable-cotype
             (require 'cotype nil 'noerror)
             (fboundp 'cotype-maybe-enable))
    ;; Set the actor BEFORE enabling so the first `cotype open' uses
    ;; it.  `cotype-actor' is buffer-local by virtue of being
    ;; `defcustom'-defined with the standard pattern in cotype.el.
    (when (boundp 'cotype-actor)
      (setq-local cotype-actor k4k-actor-label))
    (cotype-maybe-enable)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.k4k\\'" . k4k-mode))

(provide 'k4k-mode)

;;; k4k-mode.el ends here
