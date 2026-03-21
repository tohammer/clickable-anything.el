# clickable-anything-mode

A minor mode for Emacs that makes any text matching a regexp clickable. Similar to `goto-address-mode`, but fully user-configurable.

## Features

- Highlight and click any text matching a regexp
- Assign different actions to different keys or mouse buttons per regexp
- Configure independently in each buffer
- Control how matches look with a custom face per regexp

## Installation

### use-package

```elisp
(use-package clickable-anything-mode
  :ensure t
  :commands clickable-anything-mode)
```

### Doom Emacs

In `packages.el`:

```elisp
(package! clickable-anything-mode)
```

In `config.el`:

```elisp
(use-package! clickable-anything-mode)
```

## Configuration

Each entry in `clickable-anything-alist` has the form:

```
(REGEXP HANDLER &optional GROUP FACE)
```

`HANDLER` is either:
- A **function** called with the matched text — mouse-2 and `C-c RET` activate it by default.
- An **alist** of `("KEY" . FUNCTION)` pairs — each key invokes its function with the matched text. No default keys are added; only `RET` falls through to the major mode.

`GROUP` is the regexp submatch index (default 0, i.e. the full match).  
`FACE` is the overlay face (default `clickable-anything-face`, which underlines).

### Examples

Single handler:

```elisp
(setq clickable-anything-alist
  `(("https?://[^ \t\n]+" #'browse-url)))
```

Per-key dispatch:

```elisp
(setq clickable-anything-alist
  `(("https?://[^ \t\n]+"
     (("<mouse-2>" . browse-url)
      ("<mouse-3>" . kill-new)))))
```

Pull request references (e.g. `(#123)` in commit messages):

```elisp
(defun my/open-pr (number)
  "Open pull request NUMBER in the browser."
  (browse-url (format "https://github.com/my-org/my-repo/pull/%s" number)))

(defun my/show-pr-info (number)
  "Show information about pull request NUMBER."
  (message "PR #%s — fetch info here" number))

(defvar my/clickable-pr
  `(,(rx " (#" (group (+ num)) ")")
    (("C-c RET"   . my/show-pr-info)
     ("<mouse-2>" . my/show-pr-info)
     ("C-c C-o"   . my/open-pr)
     ("<mouse-3>" . my/open-pr))
    1))  ; submatch 1 captures the number only

(setq clickable-anything-alist (list my/clickable-pr))
```

The `1` at the end selects submatch group 1 (just the number, without the surrounding parentheses), which is what gets passed to the handler functions.

Enable the mode:

```elisp
(clickable-anything-mode 1)
```

To enable it automatically in a specific mode:

```elisp
(add-hook 'text-mode-hook #'clickable-anything-mode)
```
