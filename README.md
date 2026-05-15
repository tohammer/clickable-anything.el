# clickable-anything-mode

Minor mode that makes any regexp-matched text clickable via overlays. Similar to `goto-address-mode` but fully configurable per buffer.

## Installation

### use-package (Emacs 29+)

```elisp
(use-package clickable-anything-mode
  :vc (:url "https://github.com/tohammer/clickable-anything.el")
  :commands clickable-anything-mode)
```

### Doom Emacs

In `packages.el`:

```elisp
(package! clickable-anything-mode
  :recipe (:host github :repo "tohammer/clickable-anything.el"))
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

- **REGEXP** — regular expression to match
- **HANDLER** — a function called with the matched text, or an alist of `("KEY" . FUNCTION)` pairs for per-key dispatch. When a function, `<mouse-2>` and `C-c RET` activate it. When an alist, only `RET` falls through to the major mode.
- **GROUP** — submatch index (default 0). Can be a list of indices — the first with a non-nil match is used. Useful when alternating branches each have their own group, e.g. `(1 2)`.
- **FACE** — overlay face (default `clickable-anything-face`, underlined).

`clickable-anything-alist` is buffer-local; set it with `setq-local` or via a mode hook.

### Examples

Single handler (URL):

```elisp
(setq-local clickable-anything-alist
  '(("https?://[^ \t\n]+" browse-url)))
```

Per-key dispatch with submatch:

```elisp
(setq-local clickable-anything-alist
  `((,(rx "(#" (group (+ num)) ")")
     (("<mouse-2>" . my/open-pr)
      ("<mouse-3>" . my/copy-pr))
     1)))
```

Alternating groups (e.g. `[TICKET-1]` or `Issue: TICKET-1`):

```elisp
(setq-local clickable-anything-alist
  `((,(rx (or (seq "[" (group (+ (in "A-Z")) "-" (+ num)) "]")
             (seq "Issue:" (* " ") (group (+ (in "A-Z")) "-" (+ num)))))
     my/open-ticket
     (1 2))))
```

Enable the mode:

```elisp
(clickable-anything-mode 1)
;; or via hook:
(add-hook 'magit-revision-mode-hook #'clickable-anything-mode)
```

## AI Disclaimer

This package was developed with the help of AI coding agents.
