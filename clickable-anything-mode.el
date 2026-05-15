;;; clickable-anything-mode.el --- Configurable clickable regexps via overlays -*- lexical-binding: t; -*-

;; Author: Tobias Hammer <tohammer@users.noreply.github.com>
;; Maintainer: Tobias Hammer <tohammer@users.noreply.github.com>
;; Copyright (C) 2025 Tobias Hammer
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (seq "2.24"))
;; Keywords: convenience, mouse, links
;; URL: https://github.com/tohammer/clickable-anything.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Minor mode that makes any regexp-matched text clickable via overlays.
;; Similar to goto-address-mode but fully user-configurable per buffer.
;;
;; Each entry in `clickable-anything-alist' has the form:
;;
;;   (REGEXP HANDLER &optional GROUP FACE)
;;
;; HANDLER is either a function called with the matched text, or an alist
;; of (KEY-STRING . FUNCTION) pairs for per-key dispatch, e.g.:
;;   '(("<mouse-2>" . browse-url) ("<mouse-3>" . kill-new))
;;
;; GROUP is the submatch index (default 0).  It can also be a list of
;; indices — the first one with a non-nil match is used.  This is useful
;; when a regexp uses alternation and each branch has its own group.

;;; Code:

(require 'seq)

(defgroup clickable-anything nil
  "Clickable regexps in buffers."
  :group 'convenience)

(defface clickable-anything-face
  '((t (:underline t)))
  "Default face for clickable regexps."
  :group 'clickable-anything)

(defcustom clickable-anything-alist nil
  "List of clickable regexp definitions.

Each entry has the form:

  (REGEXP HANDLER &optional GROUP FACE)

REGEXP   - regular expression
HANDLER  - either a function called with the matched text, or an alist of
           (KEY-STRING . FUNCTION) pairs mapping key sequences to functions.
           When an alist, each function is called with the matched text.
           The first entry is used as the default action for \\[clickable-anything--call-at-point].
           Example: ((\"<mouse-2>\" . #\\='browse-url) (\"<mouse-3>\" . #\\='kill-new))
GROUP    - submatch index (default 0), or a list of indices tried in order —
           the first group with a non-nil match is used.  Useful when a regex
           uses alternation and each branch has its own capture group.
           Example: (1 2) tries group 1 first, then group 2.
FACE     - face for overlay (default `clickable-anything-face`)

This variable is buffer-local."
  :type '(repeat
          (list
           regexp
           (choice function
                   (alist :key-type string :value-type function))
           (choice (const :tag "Full match" 0)
                   integer
                   (repeat :tag "Try groups in order" integer))
           (choice (const :tag "Default face" nil) face)))
  :local t
  :group 'clickable-anything)

(defun clickable-anything--fallthrough ()
  "Call the original RET binding from the major mode."
  (interactive)
  (let* ((overlays (overlays-at (point)))
         (keymaps (delq nil (mapcar (lambda (o) (overlay-get o 'keymap)) overlays))))
    ;; Temporarily remove overlay keymaps to find the underlying binding
    (unwind-protect
        (progn
          (dolist (o overlays)
            (overlay-put o 'keymap nil))
          (let ((cmd (key-binding (kbd "RET"))))
            (when cmd
              (call-interactively cmd))))
      ;; Restore overlay keymaps
      (cl-loop for o in overlays
               for km in keymaps
               do (overlay-put o 'keymap km)))))

(defvar clickable-anything-base-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET") #'clickable-anything--fallthrough)
    m)
  "Base keymap inherited by all clickable-anything overlay keymaps.
Only provides RET fallthrough to the underlying major-mode binding.")

(defvar clickable-anything-highlight-keymap
  (let ((m (make-sparse-keymap)))
    (set-keymap-parent m clickable-anything-base-keymap)
    (define-key m (kbd "<mouse-2>") #'clickable-anything--call-at-point)
    (define-key m (kbd "C-c RET") #'clickable-anything--call-at-point)
    m)
  "Keymap for clickable-anything overlays with a single-function handler.
Adds mouse-2 and C-c RET as default activation keys on top of the base keymap.")

(defun clickable-anything--make-keymap (handler text)
  "Return an overlay keymap for HANDLER and matched TEXT.
HANDLER is either a function or an alist of (KEY-STRING . FUNCTION) pairs.
When a function, returns `clickable-anything-highlight-keymap' (mouse-2,
C-c RET, RET fallthrough).  When an alist, builds a keymap inheriting only
RET fallthrough, with each user-specified key bound to its function."
  (if (functionp handler)
      clickable-anything-highlight-keymap
    (let ((m (make-sparse-keymap)))
      (set-keymap-parent m clickable-anything-base-keymap)
      (dolist (binding handler)
        (let ((fn (cdr binding)))
          (define-key m (kbd (car binding))
            (lambda () (interactive) (funcall fn text)))))
      m)))

(defun clickable-anything--call-at-point (&optional event)
  "Invoke the handler of the clickable overlay at point or at EVENT position."
  (interactive (list last-input-event))
  (save-excursion
    (when event (posn-set-point (event-end event)))
    (let ((fun (seq-some (lambda (e) (overlay-get e 'clickable-anything))
                         (overlays-at (point)))))
      (when fun
        (funcall fun)))))

(defun clickable-anything--fontify-region (start end)
  "Apply clickable overlays between START and END."
  (clickable-anything--unfontify start end)
  (save-excursion
    (let ((case-fold-search nil))
      (dolist (entry clickable-anything-alist)
        (pcase-let ((`(,regexp ,handler ,group ,face) entry))
          (let ((groups (cond ((null group)   '(0))
                              ((listp group)  group)
                              (t              (list group))))
                (face (or face 'clickable-anything-face)))
            (goto-char start)
            (while (re-search-forward regexp end t)
              (let* ((active (seq-find (lambda (g)
                                         (and (match-beginning g) (match-end g)))
                                       groups))
                     (mb (when active (match-beginning active)))
                     (me (when active (match-end active))))
                (when (and mb me)
                  (let* ((text (buffer-substring-no-properties mb me))
                         (default-fn (if (functionp handler) handler (cdar handler)))
                         (ov (make-overlay mb me)))
                    (overlay-put ov 'face face)
                    (overlay-put ov 'mouse-face 'highlight)
                    (overlay-put ov 'priority 100)
                    (overlay-put ov 'help-echo "click to activate")
                    (overlay-put ov 'clickable-anything (lambda () (funcall default-fn text)))
                    (overlay-put ov 'keymap (clickable-anything--make-keymap handler text))
                    (overlay-put ov 'evaporate t)))))))))))

(defun clickable-anything--unfontify (start end)
  "Remove `clickable-anything' fontification from the given region."
  (dolist (overlay (overlays-in start end))
    (when (overlay-get overlay 'clickable-anything)
      (delete-overlay overlay))))

;;;###autoload
(define-minor-mode clickable-anything-mode
  "Minor mode to make configurable regexps clickable using overlays.

Regexps are defined in `clickable-anything-alist`.
Handlers receive the matched text."
  :lighter ""
  (cond
   (clickable-anything-mode
    (jit-lock-register #'clickable-anything--fontify-region))
   (t
    (jit-lock-unregister #'clickable-anything--fontify-region)
    (save-restriction
      (widen)
      (clickable-anything--unfontify (point-min) (point-max))))))

(provide 'clickable-anything-mode)

;;; clickable-anything-mode.el ends here
