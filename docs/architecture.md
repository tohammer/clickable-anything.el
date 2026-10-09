# Architecture and implementation notes

This document describes how `clickable-anything-mode` works and the Emacs
behaviours it has to work around. Read it before changing how overlays,
keymaps or fontification are set up.

## Overview

```
clickable-anything-mode on
  └─ jit-lock-register clickable-anything--fontify-region
       └─ for each visible chunk (whole lines):
            remove our overlays in the chunk
            for each (REGEXP HANDLER GROUP FACE) in clickable-anything-alist:
              re-search-forward in the chunk
              make overlay on the chosen group with:
                face, mouse-face, help-echo, priority 100, evaporate
                clickable-anything  → closure calling the default action
                keymap              → handler keymap composed with the
                                      `keymap' text property underneath
```

- **Fontification** is done by jit-lock, so only displayed text is scanned
  and edited text is rescanned automatically.
- **Overlays** are tagged with the `clickable-anything` property. That tag
  is how the package finds its own overlays when it removes them.
- **Default action**: the overlay's `clickable-anything` property holds a
  closure that calls the handler (or the first alist entry) with the
  matched text. `clickable-anything-activate` runs it for point or a mouse
  event.

## Keymaps

### Overlay keymaps replace text-property keymaps

When looking up a key, Emacs takes the `keymap` property at point with
`get-char-property`. That returns the overlay's value whenever an overlay
there has a `keymap` property, and the text property only when none
does. The two are **not merged**: an overlay keymap hides the
text-property keymap at the same position completely.

Major modes such as magit and compilation-mode put their per-section or
per-error keymaps on the text as `keymap` properties. In a magit log, for
example, every commit line carries `magit-commit-section-map`, which maps
RET to `magit-show-commit`. With a plain overlay keymap on a `(#12)` link,
RET on the link fell through to `magit-mode-map`'s generic binding instead.
The section's context-menu entries were lost the same way. Keys from mode
keymaps (`a`, `v`, `w` in magit) were never affected, because overlay
keymaps sit above mode keymaps, not in place of them.

**Current solution** (`clickable-anything--overlay-keymap`): when an
overlay is created, its keymap is built as

```elisp
(make-composed-keymap OWN (get-text-property START 'keymap))
```

so the handler's keys win and every other key resolves through the
keymap the text already had. The test
`clickable-anything-test-keeps-text-property-keymap` covers this.

**Limitation**: the text-property keymap is read once, at fontification
time, from the first character of the match. If a package changes the
`keymap` property without changing the text, the overlay keeps the old
keymap until the text is fontified again. Magit and compilation-mode
reinsert text on refresh, so this does not affect them.

### Earlier approach: RET fallthrough (removed in 0.2)

Version 0.1 bound RET in every overlay keymap to
`clickable-anything--fallthrough`. That command took the keymap off every
overlay at point, ran whatever RET was bound to underneath, and put the
keymaps back. It fixed only RET and had two bugs:

- It used `cl-loop` without `(require 'cl-lib)`. If the file was compiled
  without cl-lib loaded, the loop compiled as a function call and failed
  with `(void-variable for)`. The error happened in the cleanup, after
  the keymaps had been removed, so the link stopped working entirely.
  Doom happened to load cl-lib before compiling, which hid this.
- It removed keymaps from *all* overlays at point but saved only the
  non-nil ones (`delq nil`), then restored them by position. With another
  overlay at point (hl-line, flycheck, region), keymaps went to the wrong
  overlays.

Composing keymaps makes the fallthrough unnecessary.

## Handler dispatch

`HANDLER` is treated as a key alist only if it is a list whose first
element is a `(STRING . FUNCTION)` pair
(`clickable-anything--alist-handler-p`). Anything else is treated as a
function. 0.1 checked `functionp` instead, which is nil for a symbol that
is not defined *yet*. Such a handler was then walked as an alist and
signalled `wrong-type-argument` inside jit-lock. Now an undefined handler
only fails when it is activated, with a normal `void-function` error.

Function handlers share `clickable-anything-highlight-keymap`
(`<mouse-2>`, `C-c RET`). Alist handlers get a fresh keymap per match,
with one closure per key capturing the matched text. They don't bind
the default keys.

### Which buffer a handler runs in

For a mouse click, Emacs looks up the key in the keymaps of the *clicked*
window's buffer, but runs the command with the *selected* window's buffer
current. Clicking `<mouse-3>` on a link in a magit window that isn't
selected therefore ran an alist handler in some other buffer. Handlers
that depend on the current buffer (its `default-directory`, its git
repository, buffer-local variables) then acted on the wrong repository.

- Alist handler closures capture the buffer they were created in and
  run the function with `with-current-buffer`.
- `clickable-anything-activate` (used by function handlers) takes the
  buffer and position from the mouse event's `posn`.

The test `clickable-anything-test-mouse-click-in-unselected-window`
simulates both cases with a synthetic event.

## Fontification details

- **Refontify on enable.** `jit-lock-register` calls `(jit-lock-mode t)`,
  which always marks the whole buffer for refontification. Enabling the
  mode in a buffer that is already displayed, or enabling it again after
  changing `clickable-anything-alist`, therefore applies the alist
  without any extra code. The tests
  `clickable-anything-test-enable-in-fontified-buffer` and
  `clickable-anything-test-reenable-applies-new-alist` pin this
  behaviour.
- **Line-bounded matching.** jit-lock hands over chunks that start and end
  at line boundaries, and the search is bounded by the chunk end. A regexp
  that spans lines can therefore match only partly or not at all.
- **Case-sensitive matching.** `case-fold-search` is bound to nil.
- **Empty matches.** A regexp that can match the empty string (`x*`)
  made 0.1 loop forever inside redisplay. The search loop now moves one
  character on after an empty match, and empty spans get no overlay.
- **Evaporating overlays.** Overlays have `evaporate` set, so deleting the
  matched text deletes the overlay.
- **Major-mode changes.** `kill-all-local-variables` removes the jit-lock
  function but not overlays. The mode adds
  `clickable-anything--teardown` to the buffer-local
  `change-major-mode-hook` so overlays and keymaps do not linger.

## Testing

`make test` runs the ERT suite in `test/` under `emacs -Q --batch`.
`make compile` byte-compiles with warnings treated as errors, which would
have caught the missing `cl-lib` require. `make checkdoc` lints the
docstrings. `make` runs all three.

## Open points

- **One keymap per match for alist handlers.** Each match gets its own
  keymap and closures, plus a composed keymap when there is a
  text-property keymap. That is cheap for typical buffers. If large
  buffers become slow, build one keymap per alist entry and have the
  bound commands read the matched text from the overlay at point or at
  the click position.
- **Package naming.** The file and feature are `clickable-anything-mode`,
  but the symbols use the `clickable-anything-` prefix, and the face ends
  in `-face`. package-lint will flag both. Renaming to
  `clickable-anything.el` and a face called `clickable-anything` is a
  breaking change; do it before a MELPA submission.
