;;; clickable-anything-mode.el --- Configurable clickable regexps via overlays -*- lexical-binding: t; -*-

;; Author: Tobias Hammer
;; Maintainer: Tobias Hammer
;; Version: 0.1
;; Package-Requires: ((emacs "28.1") (seq "2.24"))
;; Keywords: convenience, mouse, links
;; URL: https://github.com/yourname/clickable-anything
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; clickable-anything-mode is a minor mode similar to goto-address-mode,
;; but configurable via regex/handler pairs and implemented using overlays.
;;
;; Features:
;;  - Lazy highlighting using jit-lock
;;  - Overlay-based (safe with font-lock modes)
;;  - Match group support
;;  - Buffer-local configuration
;;  - Mouse and keyboard activation
;;  - MELPA-ready
;;
;; Configuration entries:
;;
;;   (REGEXP HANDLER &optional GROUP FACE)
;;
;; HANDLER is called with the matched text.

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

REGEXP  - regular expression
HANDLER - function called with matched text
GROUP   - submatch index (default 0)
FACE    - face for overlay (default `clickable-anything-face`)

This variable is buffer-local."
  :type '(repeat
          (list
           regexp
           function
           (choice (const :tag "Full match" 0) integer)
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

(defvar clickable-anything-highlight-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "<mouse-2>") #'clickable-anything--call-at-point)
    (define-key m (kbd "RET") #'clickable-anything--fallthrough)
    (define-key m (kbd "C-c RET") #'clickable-anything--call-at-point)
    m)
  "Keymap active on clickable-anything overlays.")

(defun clickable-anything--call-at-point (&optional event)
  "Invoke the handler of the clickable overlay at point or at EVENT position."
  (interactive (list last-input-event))
  (save-excursion
    (when event (posn-set-point (event-end event)))
    (let ((fun (seq-find #'identity (seq-map
                                   (lambda (e) (overlay-get e 'clickable-anything))
                                   (overlays-at (point))))))
      (when fun
        (funcall fun)))))

(defun clickable-anything--fontify-region (start end)
  "Apply clickable overlays between START and END."
  (clickable-anything--unfontify start end)
  (save-excursion
    (let ((case-fold-search nil))
      (dolist (entry clickable-anything-alist)
        (pcase-let ((`(,regexp ,handler ,group ,face) entry))
          (let ((group (or group 0))
                (face (or face 'clickable-anything-face)))
            (goto-char start)
            (while (re-search-forward regexp end t)
              (let ((mb (match-beginning group))
                    (me (match-end group)))
                (when (and mb me)
                  (let ((ov (make-overlay mb me nil nil nil))
                        (text (buffer-substring-no-properties mb me)))
                    (overlay-put ov 'face face)
                    (overlay-put ov 'mouse-face 'highlight)
                    (overlay-put ov 'priority 100)
                    (overlay-put ov 'help-echo "mouse-2 or C-c RET: activate")
                    (overlay-put ov 'clickable-anything (lambda () (funcall handler text)))
                    (overlay-put ov 'keymap clickable-anything-highlight-keymap)
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
