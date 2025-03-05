# EIN - Emacs IPython Notebook (Peter's Fork)

> In Emacs' realm where code and data meet,
> The Python notebooks find their home complete.
> With cells of code that run at your command,
> And output clear for you to understand.
> Through EIN's grace, your data's stories told,
> As charts and graphs their secrets do unfold.

I wanted to hack around a bit on [EIN](https://github.com/millejoh/emacs-ipython-notebook/), so I made this fork.

**If you make changes, make sure to uncomment package-generate-autoloads in your config so that the ein-autoloads.el file gets updated correctly.**

## TODO

- [ ] plotting doesn't work. Try running with inlined images set to nil and see if it
      pops up

## Installing

I install via running the following lines on initialization:

```elisp
(package-generate-autoloads "ein" "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/")
(load-file "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/ein-autoloads.el")
```

I recommend commenting out the `package-generate-autoloads` call unless you're actively working on the repo. Otherwise, it will needlessly update the autoloads when no changes have been made.

This requires the emacs package `python-black` as well as the python package `black`. Do `pip install black` to get the latter.

Below is my full config. Replace `~/.emacs.d/lisp/emacs-ipython-notebook` with your local path to the repo.

```elisp
(use-package ein
  :ensure nil
  :init
  (add-hook 'ein:notebook-mode-hook 'jedi:setup)
  (package-generate-autoloads "ein" "/Users/peter.wills@equipmentshare.com/.emacs.d/lisp/emacs-ipython-notebook/lisp/")
  (load-file
   "/Users/peter.wills@equipmentshare.com/.emacs.d/lisp/emacs-ipython-notebook/lisp/ein-autoloads.el")
  (load-file
   "/Users/peter.wills@equipmentshare.com/.emacs.d/lisp/emacs-ipython-notebook/lisp/ein-init.el")
  :config
  ;; open files as ipython notebooks automagically
  (add-hook 'ein:ipynb-mode-hook 'ein:maybe-open-file-as-notebook)
  :custom
  (ein:completion-backend 'ein:use-ac-backend) ;; ac-jedi-backend doesn't work
  (ein:complete-on-dot t)
  (ein:truncate-long-cell-output nil)
  (ein:auto-save-on-execute t)
  (ein:auto-black-on-execute t)
  (ein:output-area-inlined-images t)
  (ein:slice-image t)
  (ein:urls "http://127.0.0.1:8888")
  (ein:notebook-default-home-directory "/Users/peter.wills@equipmentshare.com")
  :bind
  ("C-x M-w" . ein:notebook-save-to-command)
  ("C-c C-x C-c" . ein:worksheet-clear-all-output)
  ("C-c C-x C-k" . ein:nuke-and-pave)
  ("C-c C-x C-f" . ein:new-notebook)
  ("C-c b c" . ein:worksheet-python-black-cell))
```

## Changes

### `slice-image`

I reinstated the `slice-image` functionality, which you can see in the definition of `ein:insert-image` in `ein-cell.el`. This was removed from EIN, but I liked using it.

### Autosave

if `ein:auto-save-on-execute` is non-nil, then the notebook is saved on each cell execution.

### Blacken cell

There is an `ein:worksheet-python-black-cell` function that blackens the current cell. This will fail if the cell is not syntactically valid python code (e.g. markdown).

There is also an `ein:auto-black-on-execute` argument that will (if non-nil) use black to format cells upon execution.

TODO Rework this so that the user can still import EIN without having `python-black` installed.

### Nuke and pave

Added `ein:nuke-and-pave` which clears all output, restarts kernel, and moves cursor to the start of the buffer.

### Open file as notebook

Added `ein:maybe-open-file-as-notebook`, which will open a notebook buffer corresponding to the buffer if the buffer is in `ipynb-mode`. It's good to add this to the `find-file-hook` so that notebooks get automatically opened upon visiting.

### New notebook

Added `ein:new-notebook` that just created an empty `.ipynb` file from a template, and visits the file. This works in conjunction with the above `ein:maybe-open-file-as-notebook` so that when the file is visited, it is opened as a notebook.

## Keymap (C-h m)

```
key             binding
---             -------

C-c		Prefix Command
C-x		Prefix Command
ESC		Prefix Command
<C-down>	ein:worksheet-goto-next-input-km
<C-up>		ein:worksheet-goto-prev-input-km
<M-S-return>	ein:worksheet-execute-cell-and-insert-below-km
<M-down>	ein:worksheet-not-move-cell-down-km
<M-up>		ein:worksheet-not-move-cell-up-km

C-x C-s		ein:notebook-save-notebook-command-km
C-x C-w		ein:notebook-rename-command-km

M-RET		ein:worksheet-execute-cell-and-goto-next-km
M-,		ein:pytools-jump-back-command
M-.		ein:pytools-jump-to-source-command

C-c C-a		ein:worksheet-insert-cell-above-km
C-c C-b		ein:worksheet-insert-cell-below-km
C-c C-c		ein:worksheet-execute-cell-km
C-u C-c C-c    		ein:worksheet-execute-all-cells
C-c C-e		ein:worksheet-toggle-output-km
C-c C-f		ein:file-open-km
C-c C-k		ein:worksheet-kill-cell-km
C-c C-l		ein:worksheet-clear-output-km
C-c RET		ein:worksheet-merge-cell-km
C-c C-n		ein:worksheet-goto-next-input-km
C-c C-o		ein:notebook-open-km
C-c C-p		ein:worksheet-goto-prev-input-km
C-c C-q		ein:notebook-kill-kernel-then-close-command-km
C-c C-r		ein:notebook-reconnect-session-command-km
C-c C-s		ein:worksheet-split-cell-at-point-km
C-c C-t		ein:worksheet-toggle-cell-type-km
C-c C-u		ein:worksheet-change-cell-type-km
C-c C-v		ein:worksheet-set-output-visibility-all-km
C-c C-w		ein:worksheet-copy-cell-km
C-c C-x		Prefix Command
C-c C-y		ein:worksheet-yank-cell-km
C-c C-z		ein:notebook-kernel-interrupt-command-km
C-c ESC		Prefix Command
C-c C-S-l	ein:worksheet-clear-all-output-km
C-c C-#		ein:notebook-close-km
C-c C-$		ein:tb-show-km
C-c C-/		ein:notebook-scratchsheet-open-km
C-c C-;		ein:shared-output-show-code-cell-at-point-km
C-c <down>	ein:worksheet-move-cell-down-km
C-c <up>	ein:worksheet-move-cell-up-km

C-c C-x C-r	ein:notebook-restart-session-command-km
```
