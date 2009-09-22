;;; clojure-mode.el --- Major mode for Clojure code

;; Copyright (C) 2007, 2008, 2009 Jeffrey Chu, Lennart Staflin, Phil Hagelberg
;;
;; Authors: Jeffrey Chu <jochu0@gmail.com>
;;          Lennart Staflin <lenst@lysator.liu.se>
;;          Phil Hagelberg <technomancy@gmail.com>
;; URL: http://www.emacswiki.org/cgi-bin/wiki/ClojureMode
;; Version: 1.5
;; Keywords: languages, lisp

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Provides font-lock, indentation, and navigation for the Clojure
;; language. (http://clojure.org)

;;; Installation:

;; If you use ELPA, you can install via the M-x package-list-packages
;; interface. This is preferrable as you will have access to updates
;; automatically.

;; If you need to install by hand for some reason:

;; (0) Add this file to your load-path, usually the ~/.emacs.d directory.
;; (1) Either:
;;     Add this to your .emacs config: (require 'clojure-mode)
;;     Or generate autoloads with the `update-directory-autoloads' function.

;; The clojure-install function can check out and configure all the
;; dependencies get going with Clojure, including SLIME integration.
;; To use this function, you may have to manually load clojure-mode.el
;; using M-x load-file or M-x eval-buffer.

;; Users of older Emacs (pre-22) should get version 1.4:
;; http://github.com/technomancy/clojure-mode/tree/1.4

;; Paredit users:

;; Download paredit v21 or greater
;;    http://mumble.net/~campbell/emacs/paredit.el

;; Use paredit as you normally would with any other mode; for instance:
;;
;;   ;; require or autoload paredit-mode
;;   (defun lisp-enable-paredit-hook () (paredit-mode 1))
;;   (add-hook 'clojure-mode-hook 'lisp-enable-paredit-hook)

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'cl)

(defgroup clojure-mode nil
  "A mode for Clojure"
  :prefix "clojure-mode-"
  :group 'applications)

(defcustom clojure-mode-font-lock-comment-sexp nil
  "Set to non-nil in order to enable font-lock of (comment...)
forms. This option is experimental. Changing this will require a
restart (ie. M-x clojure-mode) of existing clojure mode buffers."
  :type 'boolean
  :group 'clojure-mode)

(defcustom clojure-mode-use-backtracking-indent nil
  "Set to non-nil to enable backtracking/context sensitive indentation."
  :type 'boolean
  :group 'clojure-mode)

(defcustom clojure-max-backtracking 3
  "Maximum amount to backtrack up a list to check for context."
  :type 'integer
  :group 'clojure-mode)

(defvar clojure-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map lisp-mode-shared-map)
    map)
  "Keymap for Clojure mode. Inherits from `lisp-mode-shared-map'.")

(defvar clojure-mode-syntax-table
  (let ((table (copy-syntax-table emacs-lisp-mode-syntax-table)))
    (modify-syntax-entry ?~ "'   " table)
    (modify-syntax-entry ?, "    " table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?^ "'" table)
    table))

(defvar clojure-mode-abbrev-table nil
  "Abbrev table used in clojure-mode buffers.")

(define-abbrev-table 'clojure-mode-abbrev-table ())

(defvar clojure-def-regexp "^\\s *\\((def\\S *\\s +\\(\[^ \n\t\]+\\)\\)"
  "A regular expression to match any top-level definitions.")

;;;###autoload
(defun clojure-mode ()
  "Major mode for editing Clojure code - similar to Lisp mode..
Commands:
Delete converts tabs to spaces as it moves back.
Blank lines separate paragraphs.  Semicolons start comments.
\\{clojure-mode-map}

Entry to this mode calls the value of `clojure-mode-hook'
if that value is non-nil."
  (interactive)
  (kill-all-local-variables)
  (use-local-map clojure-mode-map)
  (setq major-mode 'clojure-mode)
  (setq mode-name "Clojure")
  (lisp-mode-variables nil)
  (set-syntax-table clojure-mode-syntax-table)

  (setq local-abbrev-table clojure-mode-abbrev-table)

  (set (make-local-variable 'comment-start-skip)
       "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\)\\(;+\\|#|\\) *")
  (set (make-local-variable 'lisp-indent-function)
       'clojure-indent-function)
  (set (make-local-variable 'font-lock-multiline) t)

  (setq lisp-imenu-generic-expression
        `((nil ,clojure-def-regexp 2)))
  (setq imenu-create-index-function
        (lambda ()
          (imenu--generic-function lisp-imenu-generic-expression)))

  (add-to-list 'font-lock-extend-region-functions
               'clojure-font-lock-extend-region-def t)

  (when clojure-mode-font-lock-comment-sexp
    (add-to-list 'font-lock-extend-region-functions
                 'clojure-font-lock-extend-region-comment t)
    (make-local-variable 'clojure-font-lock-keywords)
    (add-to-list 'clojure-font-lock-keywords
                 'clojure-font-lock-mark-comment t)
    (set (make-local-variable 'open-paren-in-column-0-is-defun-start) nil))

  (setq font-lock-defaults
        '(clojure-font-lock-keywords    ; keywords
          nil nil
          (("+-*/.<>=!?$%_&~^:@" . "w")) ; syntax alist
          nil
          (font-lock-mark-block-function . mark-defun)
          (font-lock-syntactic-face-function
           . lisp-font-lock-syntactic-face-function)))

  (run-mode-hooks 'clojure-mode-hook)

  ;; Enable curly braces when paredit is enabled in clojure-mode-hook
  (when (and (featurep 'paredit) paredit-mode (>= paredit-version 21))
    (define-key clojure-mode-map "{" 'paredit-open-curly)
    (define-key clojure-mode-map "}" 'paredit-close-curly)))

;; (define-key clojure-mode-map "{" 'self-insert-command)
;; (define-key clojure-mode-map "}" 'self-insert-command)

(defun clojure-font-lock-def-at-point (point)
  "Find the position range between the top-most def* and the
fourth element afterwards. Note that this means there's no
gaurantee of proper font locking in def* forms that are not at
top-level."
  (goto-char point)
  (condition-case nil
      (beginning-of-defun)
    (error nil))

  (let ((beg-def (point)))
    (when (and (not (= point beg-def))
               (looking-at "(def"))
      (condition-case nil
          (progn
            ;; move forward as much as possible until failure (or success)
            (forward-char)
            (dotimes (i 4)
              (forward-sexp)))
        (error nil))
      (cons beg-def (point)))))

(defun clojure-font-lock-extend-region-def ()
  "Move fontification boundaries to always include the first four
elements of a def* forms."
  (let ((changed nil))
    (let ((def (clojure-font-lock-def-at-point font-lock-beg)))
      (when def
        (destructuring-bind (def-beg . def-end) def
          (when (and (< def-beg font-lock-beg)
                     (< font-lock-beg def-end))
            (setq font-lock-beg def-beg
                  changed t)))))

    (let ((def (clojure-font-lock-def-at-point font-lock-end)))
      (when def
        (destructuring-bind (def-beg . def-end) def
          (when (and (< def-beg font-lock-end)
                     (< font-lock-end def-end))
            (setq font-lock-end def-end
                  changed t)))))
    changed))

(defun clojure-font-lock-extend-region-comment ()
  "Move fontification boundaries to always contain
  entire (comment ..) sexp. Does not work if you have a
  white-space between ( and comment, but that is omitted to make
  this run faster."
  (let ((changed nil))
    (goto-char font-lock-beg)
    (condition-case nil (beginning-of-defun) (error nil))
    (let ((pos (re-search-forward "(comment\\>" font-lock-end t)))
      (when pos
        (forward-char -8)
        (when (< (point) font-lock-beg)
          (setq font-lock-beg (point)
                changed t))
        (condition-case nil (forward-sexp) (error nil))
        (when (> (point) font-lock-end)
          (setq font-lock-end (point)
                changed t))))
    changed))

(defun clojure-font-lock-mark-comment (limit)
  "Marks all (comment ..) forms with font-lock-comment-face."
  (let (pos)
    (while (and (< (point) limit)
                (setq pos (re-search-forward "(comment\\>" limit t)))
      (when pos
        (forward-char -8)
        (condition-case nil
            (add-text-properties (1+ (point)) (progn
                                                (forward-sexp) (1- (point)))
                                 '(face font-lock-comment-face multiline t))
          (error (forward-char 8))))))
  nil)

(defconst clojure-font-lock-keywords
  (eval-when-compile
    `( ;; Definitions.
      (,(concat "(\\(?:clojure.core/\\)?\\("
                (regexp-opt '("defn" "defn-"
                              "defmulti" "defmethod"
                              "defmacro"
                              "deftest"
                              "defstruct"
                              "def" "defonce"))
                ;; Function declarations.
                "\\)\\>"
                ;; Any whitespace
                "[ \r\n\t]*"
                ;; Possibly type or metadata
                "\\(?:#^\\(?:{[^}]*}\\|\\sw+\\)[ \r\n\t]*\\)?"

                "\\(\\sw+\\)?")
       (1 font-lock-keyword-face)
       (2 font-lock-function-name-face nil t))
      ;; Control structures
      (,(concat
         "(\\(?:clojure.core/\\)?"
         (regexp-opt
          '("let" "letfn" "do"
            "cond" "condp"
            "for" "loop" "recur"
            "when" "when-not" "when-let" "when-first"
            "if" "if-let" "if-not"
            "." ".." "->" "doto"
            "and" "or"
            "dosync" "doseq" "dotimes" "dorun" "doall"
            "load" "import" "unimport" "ns" "in-ns" "refer"
            "try" "catch" "finally" "throw"
            "with-open" "with-local-vars" "binding"
            "gen-class" "gen-and-load-class" "gen-and-save-class") t)
         "\\>")
       .  1)
      ;; Built-ins
      (,(concat
         "(\\(?:clojure.core/\\)?"
         (regexp-opt
          '("implement" "proxy" "lazy-cons" "with-meta"
            "struct" "struct-map" "delay" "locking" "sync" "time" "apply"
            "remove" "merge" "interleave" "interpose" "distinct" "for"
            "cons" "concat" "lazy-cat" "cycle" "rest" "frest" "drop"
            "drop-while" "nthrest" "take" "take-while" "take-nth" "butlast"
            "reverse" "sort" "sort-by" "split-at" "partition" "split-with"
            "first" "ffirst" "rfirst" "when-first" "zipmap" "into" "set" "vec"
            "to-array-2d" "not-empty" "seq?" "not-every?" "every?" "not-any?"
            "map" "mapcat" "vector?" "list?" "hash-map" "reduce" "filter"
            "vals" "keys%2