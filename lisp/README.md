# Emacs IPython Notebook (Fork)

I wanted to hack around a bit on
[`ein`](https://github.com/millejoh/emacs-ipython-notebook/), so I made this fork.

For some reason, when I point emacs at the `lisp/` directory from that repo, it fails to
load the package. So some kind of auto-compilation/autoloading is going on that I'm not
aware of. That's why I just copied the (compiled) code directly from my `.emacs.d/elpa`
directory as a starting point.

(I've tried requiring each subpackage individually; so, doing `(require 'ein-cell)`
etc. in `ein.el`. But to no avail; they still weren't loaded.)

I branched from the commit `611468cb6aa49d6ea0b3adb2cfd3fa9f92a3196b` on the original
repo (which was the MELPA build `20200806.1552`).

**If you make changes, and want to make new functions available interactively, then make
sure to do `M-x update-directory-autoloads` in order to update `ein-autoloads.el` to
include the new function(s).**

### TODO

Figure out what `package-install` actually does in terms of building, so that I can just
have a clean(er) clone of [the original
repo](https://github.com/millejoh/emacs-ipython-notebook) that I then build off of.

# Using

Like I said, there's some voodoo I don't understand in terms of getting this to
compile/load/install nicely. Here's my hacky solution, assuming the use of
`use-package`:

1. Clone the repo
2. Create a simlink in your `.emacs.d/elpa` directory: `ln -s /path/to/repo
   .emacs.d/elpa/ein`
3. Add the chunk below to your `.emacs` file

```elisp
(use-package ein
  :ensure nil
  ;; I can't figure out how to make this work with load-path. Pointing load-path to the
  ;; directory that we symlinked to doesn't work.
  :init
  (add-hook 'ein:notebook-mode-hook 'jedi:setup)
  :config
  ;; open .ipynb files as notebooks when visited
  (add-hook 'find-file-hook 'ein:maybe-open-file-as-notebook)
  :custom
  (ein:completion-backend 'ein:use-ac-backend) ;; ac-jedi-backend doesn't work
  (ein:complete-on-dot t)
  (ein:truncate-long-cell-output nil)
  (ein:auto-save-on-execute t)
  (ein:auto-black-on-execute t)
  (ein:output-area-inlined-images t) ;; not necessary in older versions
  (ein:slice-image t) ;; doesn't do anything in new versions
  (ein:urls "8888")
  :bind
  ("C-c C-x C-c" . ein:worksheet-clear-all-output)
  ("C-c C-x C-k" . ein:nuke-and-pave)
  ("C-c b c" . ein:worksheet-python-black-cell)
  ("C-c C-x C-f" . ein:new-notebook))
```

You don't have to include all that, obviously, but that's my config.

# Changes

## `slice-image`

I reinstated the `slice-image` functionality, which you can see in the definition of
`ein:insert-image` in `ein-cell.el`. This was removed from EIN, but I liked using it.

## Autosave

if `ein:auto-save-on-execute` is non-nil, then the notebook is saved on each cell
execution.

## Blacken cell

There is an `ein:worksheet-python-black-cell` function that blackens the current
cell. This will fail if the cell is not syntactically valid python code
(e.g. markdown).

There is also an `ein:auto-black-on-execute` argument that will (if non-nil) use black
to format cells upon execution.

TODO Rework this so that the user can still import EIN without having `python-black`
installed.


## Nuke and pave

Added `ein:nuke-and-pave` which clears all output, restarts kernel, and moves cursor to
the start of the buffer.

## Open file as notebook

Added `ein:maybe-open-file-as-notebook`, which will open a notebook buffer corresponding
to the buffer if the buffer is in `ipynb-mode`. It's good to add this to the
`find-file-hook` so that notebooks get automatically opened upon visiting.

## New notebook

Added `ein:new-notebook` that just created an empty `.ipynb` file from a
template, and visits the file. This works in conjunction with the above
`ein:maybe-open-file-as-notebook` so that when the file is visited, it is opened as a notebook.
