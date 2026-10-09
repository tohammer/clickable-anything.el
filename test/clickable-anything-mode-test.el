;;; clickable-anything-mode-test.el --- Tests for clickable-anything-mode -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run with:  make test

;;; Code:

(require 'ert)
(require 'rx)
(require 'clickable-anything-mode)

(defmacro clickable-anything-test--with-buffer (text alist &rest body)
  "Insert TEXT in a temp buffer, enable the mode with ALIST, run BODY."
  (declare (indent 2))
  `(with-temp-buffer
     (insert ,text)
     (setq-local clickable-anything-alist ,alist)
     (clickable-anything-mode 1)
     (jit-lock-fontify-now)
     ,@body))

(defun clickable-anything-test--overlays ()
  "Return the clickable overlays of the current buffer, in buffer order."
  (sort (seq-filter (lambda (o) (overlay-get o 'clickable-anything))
                    (overlays-in (point-min) (point-max)))
        (lambda (a b) (< (overlay-start a) (overlay-start b)))))

(defun clickable-anything-test--spans ()
  "Return the text covered by each clickable overlay."
  (mapcar (lambda (o) (buffer-substring-no-properties (overlay-start o) (overlay-end o)))
          (clickable-anything-test--overlays)))

(defun clickable-anything-test--pos (string)
  "Return the position of the first character of STRING in the buffer."
  (save-excursion
    (goto-char (point-min))
    (search-forward string)
    (match-beginning 0)))

;;;; Matching

(ert-deftest clickable-anything-test-full-match ()
  (clickable-anything-test--with-buffer "see https://a.example and http://b.example\n"
      '(("https?://[^ \n]+" ignore))
    (should (equal (clickable-anything-test--spans)
                   '("https://a.example" "http://b.example")))))

(ert-deftest clickable-anything-test-single-group ()
  (clickable-anything-test--with-buffer "Fix thing (#12)\n"
      `((,(rx "(#" (group (+ num)) ")") ignore 1))
    (should (equal (clickable-anything-test--spans) '("12")))))

(ert-deftest clickable-anything-test-group-list ()
  (clickable-anything-test--with-buffer "[ABC-1] and Issue: XYZ-2\n"
      `((,(rx (or (seq "[" (group (+ upper) "-" (+ num)) "]")
                  (seq "Issue:" (* " ") (group (+ upper) "-" (+ num)))))
         ignore (1 2)))
    (should (equal (clickable-anything-test--spans) '("ABC-1" "XYZ-2")))))

(ert-deftest clickable-anything-test-case-sensitive ()
  (clickable-anything-test--with-buffer "abc ABC\n"
      '(("ABC" ignore))
    (should (equal (clickable-anything-test--spans) '("ABC")))))

(ert-deftest clickable-anything-test-empty-match-terminates ()
  (clickable-anything-test--with-buffer "ab xx cd\n"
      '(("x*" ignore))
    (should (equal (clickable-anything-test--spans) '("xx")))))

(ert-deftest clickable-anything-test-faces ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore) ("bar" ignore 0 bold))
    (should (equal (mapcar (lambda (o) (overlay-get o 'face))
                           (clickable-anything-test--overlays))
                   '(clickable-anything-face bold)))))

(ert-deftest clickable-anything-test-evaporate ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (delete-region 1 4)
    (should (null (clickable-anything-test--overlays)))))

;;;; Handlers

(ert-deftest clickable-anything-test-function-handler ()
  (let (got)
    (clickable-anything-test--with-buffer "ticket ABC-1\n"
        `(("[A-Z]+-[0-9]+" ,(lambda (s) (setq got s))))
      (let ((pos (clickable-anything-test--pos "ABC")))
        (should (eq (key-binding (kbd "C-c RET") nil nil pos)
                    #'clickable-anything-activate))
        (should (eq (key-binding (kbd "<mouse-2>") nil nil pos)
                    #'clickable-anything-activate))
        (goto-char pos)
        (clickable-anything-activate)
        (should (equal got "ABC-1"))))))

(ert-deftest clickable-anything-test-alist-handler ()
  (let (got)
    (clickable-anything-test--with-buffer "ticket ABC-1\n"
        `(("[A-Z]+-[0-9]+"
           (("C-c C-o" . ,(lambda (s) (setq got (list 'open s))))
            ("C-c C-w" . ,(lambda (s) (setq got (list 'copy s)))))))
      (let ((pos (clickable-anything-test--pos "ABC")))
        (funcall (key-binding (kbd "C-c C-w") nil nil pos))
        (should (equal got '(copy "ABC-1")))
        ;; The default keys are not bound for alist handlers.
        (should-not (key-binding (kbd "C-c RET") nil nil pos))
        ;; `clickable-anything-activate' uses the first entry.
        (goto-char pos)
        (clickable-anything-activate)
        (should (equal got '(open "ABC-1")))))))

(ert-deftest clickable-anything-test-mouse-click-in-unselected-window ()
  ;; Mouse events use the clicked window's keymaps, but the command runs
  ;; with the selected window's buffer current.  Handlers must still run
  ;; in the buffer that holds the clickable text.
  (let ((link (generate-new-buffer "link"))
        (other (generate-new-buffer "other"))
        ran)
    (unwind-protect
        (save-window-excursion
          (with-current-buffer link
            (insert "Fix (#12)\n")
            (setq-local clickable-anything-alist
                        `((,(rx "(#" (group (+ num)) ")")
                           (("<mouse-3>" . ,(lambda (s) (push (list s (current-buffer)) ran))))
                           1)
                          ("Fix" ,(lambda (s) (push (list s (current-buffer)) ran)))))
            (clickable-anything-mode 1)
            (jit-lock-fontify-now))
          (delete-other-windows)
          (switch-to-buffer other)
          (let ((window (split-window)))
            (set-window-buffer window link)
            (dolist (click '((mouse-3 . 7) (mouse-2 . 2)))
              (let ((posn (list window (cdr click) '(0 . 0) 0 nil (cdr click)
                                '(0 . 0) nil '(0 . 0) '(1 . 1))))
                (execute-kbd-macro (vector (list (car click) posn))))))
          (should (equal (nreverse ran) `(("12" ,link) ("Fix" ,link)))))
      (kill-buffer link)
      (kill-buffer other))))

(ert-deftest clickable-anything-test-help-echo ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore) ("bar" (("C-c C-o" . ignore) ("<mouse-3>" . ignore))))
    (should (equal (mapcar (lambda (o) (overlay-get o 'help-echo))
                           (clickable-anything-test--overlays))
                   '("Activate with <mouse-2>, C-c RET"
                     "Activate with C-c C-o, <mouse-3>")))))

(ert-deftest clickable-anything-test-activate-without-link ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (goto-char (point-max))
    (should-error (clickable-anything-activate) :type 'user-error)))

(ert-deftest clickable-anything-test-undefined-handler-symbol ()
  ;; A handler that is not defined yet must not break fontification.
  (clickable-anything-test--with-buffer "foo\n"
      '(("foo" clickable-anything-test--not-defined))
    (should (equal (clickable-anything-test--spans) '("foo")))
    (goto-char 1)
    (should-error (clickable-anything-activate) :type 'void-function)))

;;;; Keymap interaction

(ert-deftest clickable-anything-test-keeps-text-property-keymap ()
  ;; Packages such as magit and compilation-mode bind RET through a
  ;; `keymap' text property.  The overlay keymap must not hide it.
  (let ((under (make-sparse-keymap)))
    (define-key under (kbd "RET") #'forward-line)
    (with-temp-buffer
      (insert (propertize "commit (#12)\n" 'keymap under))
      (setq-local clickable-anything-alist
                  `((,(rx "(#" (group (+ num)) ")") ignore 1)))
      (clickable-anything-mode 1)
      (jit-lock-fontify-now)
      (let ((pos (clickable-anything-test--pos "12")))
        (should (eq (key-binding (kbd "RET") nil nil pos) #'forward-line))
        (should (eq (key-binding (kbd "C-c RET") nil nil pos)
                    #'clickable-anything-activate))))))

(ert-deftest clickable-anything-test-ret-untouched-without-text-keymap ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (should (eq (key-binding (kbd "RET") nil nil 2)
                (key-binding (kbd "RET") nil nil 6)))))

;;;; Mode lifecycle

(ert-deftest clickable-anything-test-enable-in-fontified-buffer ()
  (with-temp-buffer
    (insert "see https://a.example\n")
    ;; Fontify the buffer before the mode is enabled.
    (jit-lock-register #'ignore)
    (jit-lock-fontify-now)
    (setq-local clickable-anything-alist '(("https?://[^ \n]+" ignore)))
    (clickable-anything-mode 1)
    (jit-lock-fontify-now)
    (should (equal (clickable-anything-test--spans) '("https://a.example")))))

(ert-deftest clickable-anything-test-reenable-applies-new-alist ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (setq-local clickable-anything-alist '(("bar" ignore)))
    (clickable-anything-mode 1)
    (jit-lock-fontify-now)
    (should (equal (clickable-anything-test--spans) '("bar")))))

(ert-deftest clickable-anything-test-disable ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (clickable-anything-mode -1)
    (should (null (clickable-anything-test--overlays)))
    (should-not (memq #'clickable-anything--fontify-region jit-lock-functions))))

(ert-deftest clickable-anything-test-major-mode-change ()
  (clickable-anything-test--with-buffer "foo bar\n"
      '(("foo" ignore))
    (text-mode)
    (should-not clickable-anything-mode)
    (should (null (clickable-anything-test--overlays)))))

(provide 'clickable-anything-mode-test)

;;; clickable-anything-mode-test.el ends here
