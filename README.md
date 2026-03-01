# clickable-anything-mode

A minor mode for Emacs that makes any text matching a regexp clickable. Similar to `goto-address-mode`, but fully user-configurable.

## Features

- Highlight and click any text matching a regexp
- Assign different actions to different keys or mouse buttons per regexp
- Configure independently in each buffer
- Control how matches look with a custom face per regexp

## Installation

Place `clickable-anything-mode.el` on your `load-path` and require it:

```elisp
(require 'clickable-anything-mode)
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

Enable the mode:

```elisp
(clickable-anything-mode 1)
```

To enable it automatically in a specific mode:

```elisp
(add-hook 'text-mode-hook #'clickable-anything-mode)
```
