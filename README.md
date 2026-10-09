# clickable-anything-mode

Minor mode that makes any regexp-matched text clickable via overlays. Similar to `goto-address-mode` or `bug-reference-mode`, but you choose the regexps, the handler functions and the keys, per buffer.

Typical uses: open pull-request numbers like `(#123)` or ticket IDs like `ABC-42` in a browser from magit, or jump to `file:line` locations in a compilation buffer.

## Quick start

After installing (see below), add this to your init file, then open any `text-mode` buffer containing a URL and middle-click it:

```elisp
(add-hook 'text-mode-hook
          (lambda ()
            (setq-local clickable-anything-alist
                        '(("https?://[^ \t\n]+" browse-url)))
            (clickable-anything-mode 1)))
```

## Installation

Requires Emacs 28.1 or later.

### use-package (Emacs 30+)

```elisp
(use-package clickable-anything-mode
  :vc (:url "https://github.com/tohammer/clickable-anything.el"))
```

### package-vc (Emacs 29)

```elisp
(package-vc-install "https://github.com/tohammer/clickable-anything.el")
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

- **REGEXP**: the regular expression to match. Matching is case-sensitive and works within a single line.
- **HANDLER**: either a function called with the matched text, or an alist of `("KEY" . FUNCTION)` pairs, so that each key runs a different function. Keys use `kbd` syntax, e.g. `"C-c C-o"` or `"<mouse-3>"`.
- **GROUP**: the submatch index (default 0). It can also be a list of indices; the first group that matched is used. This is useful when the branches of an `or` each have their own group, e.g. `(1 2)`.
- **FACE**: the overlay face (default `clickable-anything-face`, underlined).

`clickable-anything-alist` is buffer-local. Set it with `setq-local` in a mode hook, **before** enabling the mode. If you change it later in a buffer where the mode is already on, call `(clickable-anything-mode 1)` again to apply the change.

### Keys

| Handler      | Keys on clickable text                                      |
|--------------|-------------------------------------------------------------|
| function     | `<mouse-2>`, `C-c RET`                                      |
| key alist    | only the keys you list                                      |
| either       | `M-x clickable-anything-activate` runs the function, or the first alist entry |

All other keys keep their normal bindings on clickable text, including keys that the major mode attaches to the text itself (e.g. RET on a magit commit line or a compilation error).

The tooltip on clickable text lists the keys that activate it. To change the default keys for function handlers, edit `clickable-anything-highlight-keymap`.

### Examples

All examples can be pasted and run as they are.

URLs, with a function handler:

```elisp
(setq-local clickable-anything-alist
            '(("https?://[^ \t\n]+" browse-url)))
```

Pull-request numbers in magit, with different keys for different actions and only the number made clickable (group 1):

```elisp
(defun my/open-pr (number)
  (browse-url (concat "https://github.com/your-org/your-repo/pull/" number)))

(add-hook 'magit-log-mode-hook
          (lambda ()
            (setq-local clickable-anything-alist
                        `((,(rx "(#" (group (+ num)) ")")
                           (("C-c C-o"   . my/open-pr)
                            ("<mouse-2>" . my/open-pr)
                            ("<mouse-3>" . kill-new))
                           1)))
            (clickable-anything-mode 1)))
```

Ticket IDs written either as `[ABC-1]` or `Issue: ABC-1`, using a list of groups:

```elisp
(defun my/open-ticket (id)
  (browse-url (concat "https://tickets.example.com/browse/" id)))

(setq-local clickable-anything-alist
            `((,(rx (or (seq "[" (group (+ upper) "-" (+ num)) "]")
                        (seq "Issue:" (* " ") (group (+ upper) "-" (+ num)))))
               my/open-ticket
               (1 2)
               link)))
```

## Development

```sh
make          # byte-compile (warnings are errors), checkdoc, run tests
make test     # ERT tests only
```

Implementation notes, including how the overlay keymaps interact with major modes, are in [docs/architecture.md](docs/architecture.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

## AI Disclaimer

This package was developed with the help of AI coding agents.
