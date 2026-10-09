;;; clickable-anything-mode.el --- Configurable clickable regexps via overlays -*- lexical-binding: t; -*-

;; Author: Tobias Hammer <tohammer@users.noreply.github.com>
;; Maintainer: Tobias Hammer <tohammer@users.noreply.github.com>
;; Copyright (C) 2025 Tobias Hammer
;; Version: 0.2
;; Package-Requires: ((emacs "28.1"))
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
;; A function handler is activated with mouse-2 or C-c RET.  An alist
;; handler is activated only with its own keys.
;; `clickable-anything-activate' runs the default action (the function,
;; or the first alist entry) of the clickable text at point.
;;
;; GROUP is the submatch index (default 0).  It can also be a list of
;; indices — the first one with a non-nil match is used.  This is useful
;; when a regexp uses alternation and each branch has its own group.
;;
;; Keys that are not bound by the clickable text keep working: the
;; overlay keymap falls back to the `keymap' text property underneath it
;; (e.g. RET on a magit section or a compilation error).

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

REGEXP   - regular expression, matched case-sensitively within one line.
HANDLER  - either a function called with the matched text, or an alist of
           (KEY-STRING . FUNCTION) pairs mapping key sequences to functions.
           When an alist, each function is called with the matched text.
           The first entry is the default action for
           `clickable-anything-activate'.
GROUP    - submatch index (default 0), or a list of indices tried in order —
           the first group with a non-nil match is used.  Useful when a regex
           uses alternation and each branch has its own capture group.
           Example: (1 2) tries group 1 first, then group 2.
FACE     - face for overlay (default `clickable-anything-face').

This variable is buffer-local.  After changing it in a buffer where
`clickable-anything-mode' is already on, call the mode again with a
positive argument to apply the change."
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

(defvar clickable-anything-highlight-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "<mouse-2>") #'clickable-anything-activate)
    (define-key m (kbd "C-c RET") #'clickable-anything-activate)
    m)
  "Keymap for clickable-anything overlays with a single-function handler.")

(defun clickable-anything--alist-handler-p (handler)
  "Return non-nil if HANDLER is a list of (KEY-STRING . FUNCTION) pairs."
  (and (consp handler)
       (consp (car handler))
       (stringp (caar handler))))

(defun clickable-anything--make-keymap (handler text)
  "Return an overlay keymap for HANDLER and matched TEXT.
HANDLER is either a function or an alist of (KEY-STRING . FUNCTION)
pairs.  For a function, return `clickable-anything-highlight-keymap'.
For an alist, build a keymap binding each key to its function.  The
function runs in the current buffer, i.e. the one holding the overlay:
a mouse click in an unselected window would otherwise run it in the
selected window's buffer."
  (if (clickable-anything--alist-handler-p handler)
      (let ((m (make-sparse-keymap))
            (buffer (current-buffer)))
        (dolist (binding handler)
          (let ((fn (cdr binding)))
            (define-key m (kbd (car binding))
              (lambda ()
                (interactive)
                (with-current-buffer buffer (funcall fn text))))))
        m)
    clickable-anything-highlight-keymap))

(defun clickable-anything--overlay-keymap (own pos)
  "Return keymap OWN, falling back to the `keymap' text property at POS.
An overlay `keymap' property replaces the text-property keymap at the
same position instead of adding to it.  Without the fallback, keys such
as RET on a magit section or a compilation error would stop working on
clickable text."
  (let ((under (get-text-property pos 'keymap)))
    (if (keymapp under)
        (make-composed-keymap own under)
      own)))

(defun clickable-anything--help-echo (handler)
  "Return the help-echo string for HANDLER."
  (concat "Activate with "
          (if (clickable-anything--alist-handler-p handler)
              (mapconcat #'car handler ", ")
            "<mouse-2>, C-c RET")))

(defun clickable-anything-activate (&optional event)
  "Run the default action of the clickable text at point.
When called from a mouse EVENT, use the clicked position instead.  The
default action is the handler function, or the first function of an
alist handler."
  (interactive (list last-nonmenu-event))
  (let* ((posn (and (mouse-event-p event) (event-end event)))
         (window (and posn (posn-window posn)))
         (buffer (if (windowp window) (window-buffer window) (current-buffer)))
         (pos (if posn (posn-point posn) (point))))
    (with-current-buffer buffer
      (let ((fun (and pos
                      (seq-some (lambda (o) (overlay-get o 'clickable-anything))
                                (overlays-at pos)))))
        (if fun
            (funcall fun)
          (user-error "No clickable text here"))))))

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
                (face (or face 'clickable-anything-face))
                (default-fn (if (clickable-anything--alist-handler-p handler)
                                (cdar handler)
                              handler))
                (help (clickable-anything--help-echo handler)))
            (goto-char start)
            (while (and (< (point) end)
                        (re-search-forward regexp end t))
              ;; A regexp that can match the empty string would otherwise
              ;; match at the same position forever.
              (when (= (match-beginning 0) (match-end 0))
                (goto-char (min end (1+ (point)))))
              (let* ((active (seq-find #'match-beginning groups))
                     (mb (and active (match-beginning active)))
                     (me (and active (match-end active))))
                (when (and mb (< mb me))
                  (let ((text (buffer-substring-no-properties mb me))
                        (ov (make-overlay mb me)))
                    (overlay-put ov 'face face)
                    (overlay-put ov 'mouse-face 'highlight)
                    (overlay-put ov 'priority 100)
                    (overlay-put ov 'help-echo help)
                    (overlay-put ov 'clickable-anything (lambda () (funcall default-fn text)))
                    (overlay-put ov 'keymap
                                 (clickable-anything--overlay-keymap
                                  (clickable-anything--make-keymap handler text)
                                  mb))
                    (overlay-put ov 'evaporate t)))))))))))

(defun clickable-anything--unfontify (start end)
  "Remove `clickable-anything' overlays between START and END."
  (dolist (overlay (overlays-in start end))
    (when (overlay-get overlay 'clickable-anything)
      (delete-overlay overlay))))

(defun clickable-anything--teardown ()
  "Stop fontifying and remove all clickable overlays in the current buffer."
  (jit-lock-unregister #'clickable-anything--fontify-region)
  (remove-hook 'change-major-mode-hook #'clickable-anything--teardown t)
  (save-restriction
    (widen)
    (clickable-anything--unfontify (point-min) (point-max))))

;;;###autoload
(define-minor-mode clickable-anything-mode
  "Minor mode to make configurable regexps clickable using overlays.

Regexps are defined in `clickable-anything-alist'.
Handlers receive the matched text."
  :lighter ""
  (cond
   (clickable-anything-mode
    ;; Also marks the whole buffer for refontification, so enabling the
    ;; mode again applies a changed `clickable-anything-alist'.
    (jit-lock-register #'clickable-anything--fontify-region)
    ;; `kill-all-local-variables' drops the jit-lock function but would
    ;; leave the overlays and their keymaps behind.
    (add-hook 'change-major-mode-hook #'clickable-anything--teardown nil t))
   (t
    (clickable-anything--teardown))))

(provide 'clickable-anything-mode)

;;; clickable-anything-mode.el ends here
