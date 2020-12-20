==========================================================
 EIN - Emacs IPython Notebook (Peter's Fork)
==========================================================

I wanted to hack around a bit on
`EIN <https://github.com/millejoh/emacs-ipython-notebook/>`__, so I
made this fork.

**If you make changes, make sure to uncomment package-generate-autoloads in your
config so that the ein-autoloads.el file gets updated correctly.**.


Installing
=====

I install via running the following lines on initialization:

.. code:: elisp

     (package-generate-autoloads "ein" "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/")
     (load-file "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/ein-autoloads.el")

I recommend commenting out the ``package-generate-autoloads`` call unless you're
actively working on the repo. Otherwise, it will needlessly update the autoloads when no
changes have been made.

This requires `python-black <https://github.com/wbolster/emacs-python-black>__` as
well as the ``black`` package itself. Do ``pip install black`` to get the latter.

Below is my full config. Replace ``~/.emacs.d/lisp/emacs-ipython-notebook`` with your
local path to the repo.

.. code:: elisp

   (use-package ein
     :ensure nil
     :init
     (add-hook 'ein:notebook-mode-hook 'jedi:setup)
     ;; only do package-generate-autoloads when you're making changes.
     ;; (package-generate-autoloads "ein" "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/")
     (load-file "~/.emacs.d/lisp/emacs-ipython-notebook/lisp/ein-autoloads.el")
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
     (ein:slice-image t)
     ;; I set the URL explicitly, since I run my notebook servers from the terminal and
     ;; access them by URL in EIN
     (ein:urls "8888")
     :bind
     ("C-c C-x C-c" . ein:worksheet-clear-all-output)
     ("C-c C-x C-k" . ein:nuke-and-pave)
     ;; black-cell isn't really useful if you auto-black-on-execute
     ("C-c b c" . ein:worksheet-python-black-cell)
     ("C-c C-x C-f" . ein:new-notebook))

Changes
=======

``slice-image``
---------------

I reinstated the ``slice-image`` functionality, which you can see in the
definition of ``ein:insert-image`` in ``ein-cell.el``. This was removed
from EIN, but I liked using it.

Autosave
--------

if ``ein:auto-save-on-execute`` is non-nil, then the notebook is saved
on each cell execution.

Blacken cell
------------

There is an ``ein:worksheet-python-black-cell`` function that blackens
the current cell. This will fail if the cell is not syntactically valid
python code (e.g. markdown).

There is also an ``ein:auto-black-on-execute`` argument that will (if
non-nil) use black to format cells upon execution.

TODO Rework this so that the user can still import EIN without having
``python-black`` installed.

Nuke and pave
-------------

Added ``ein:nuke-and-pave`` which clears all output, restarts kernel,
and moves cursor to the start of the buffer.

Open file as notebook
---------------------

Added ``ein:maybe-open-file-as-notebook``, which will open a notebook
buffer corresponding to the buffer if the buffer is in ``ipynb-mode``.
It’s good to add this to the ``find-file-hook`` so that notebooks get
automatically opened upon visiting.

New notebook
------------

Added ``ein:new-notebook`` that just created an empty ``.ipynb`` file
from a template, and visits the file. This works in conjunction with the
above ``ein:maybe-open-file-as-notebook`` so that when the file is
visited, it is opened as a notebook.

BEGIN ORIGINAL README
=====================

.. image:: https://github.com/dickmao/emacs-ipython-notebook/blob/master/thumbnail.png
   :target: https://youtu.be/8VzWc9QeOxE
   :alt: Kaggle Notebooks in AWS

Emacs IPython Notebook (EIN) lets you run Jupyter (formerly IPython)
notebooks within Emacs.  It channels all the power of Emacs without the
idiosyncrasies of in-browser editing.

No require statements, e.g. ``(require 'ein)``, are necessary, contrary to the
`prevailing documentation`_, which should be disregarded.

*EIN has multiple* Issues_ *with minified ipynb, Doom, and Spacemacs.*

Org_ users please find ob-ein_, a jupyter Babel_ backend.

`Amazon Web Services`_ integration is in preview.

EIN was originally written by `[tkf]`_.  A jupyter Babel_ backend was first
introduced by `[gregsexton]`_.

.. |build-status|
   image:: https://github.com/millejoh/emacs-ipython-notebook/workflows/CI/badge.svg
   :target: https://github.com/millejoh/emacs-ipython-notebook/actions
   :alt: Build Status
.. |melpa-dev|
   image:: https://melpa.org/packages/ein-badge.svg
   :target: http://melpa.org/#/ein
   :alt: MELPA current version
.. _Jupyter: http://jupyter.org
.. _Babel: https://orgmode.org/worg/org-contrib/babel/intro.html
.. _Org: https://orgmode.org
.. _[tkf]: http://tkf.github.io
.. _[gregsexton]: https://github.com/gregsexton/ob-ipython

Install
=======
As described in `Getting started`_, ensure melpa's whereabouts in ``init.el`` or ``.emacs``::

   (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))

Then

::

   M-x package-refresh-contents RET
   M-x package-install RET ein RET

Alternatively, directly clone this repo and ``make install``.

Usage
=====
Start EIN using **ONE** of the following:

- Open an ``.ipynb`` file, press ``C-c C-o``, or,
- ``M-x ein:run`` launches a jupyter process from emacs, or,
- ``M-x ein:login`` to a running jupyter server, or,
- [Preview] To run on AWS, open an ``.ipynb`` file, press ``C-c C-r``.  See `Amazon Web Services`_.

``M-x ein:stop`` prompts to halt local and remote jupyter services.

Alternatively, ob-ein_.

.. _Cask: https://cask.readthedocs.io/en/latest/guide/installation.html
.. _Getting started: http://melpa.org/#/getting-started

FAQ
===

How do I...
-----------

... report a bug?
   Note EIN is tested only for *released* GNU Emacs versions
   25.1
   and later.  Pre-release versions will not work.

   First try ``emacs -Q -f package-initialize --eval "(setq debug-on-error t)"`` and reproduce the bug.  The ``-Q`` skips any user configuration that might interfere with EIN.

   Then file an issue using ``M-x ein:dev-bug-report-template``.

... display images inline?
   We find inserting images into emacs disruptive, and so default to spawning an external viewer.  To override this,
   ::

      M-x customize-group RET ein
      Ein:Output Area Inlined Images

... configure the external image viewer?
   ::

      M-x customize-group RET mailcap
      Mailcap User Mime Data

   On a typical Linux system, one might configure a viewer for MIME Type ``image/png`` as a shell command ``convert %s -background white -alpha remove -alpha off - | display -immutable``.

... get IDE-like behavior?
   The official python module for EIN is elpy_, installed separately.  Other `program modes`_ for non-python kernels may be installed with varying degrees of EIN compatibility.

... send expressions from a python buffer to a running kernel?
   Unpublicized keybindings *exclusively* for the Python language ``C-c C-/ e`` and ``C-c C-/ r`` send the current statement or region respectively to a running kernel.  If the region is not set, ``C-c C-/ r`` sends the entire buffer.  You must manually inspect the ``*ein:shared output*`` buffer for errors.

.. _Issues: https://github.com/millejoh/emacs-ipython-notebook/issues
.. _prevailing documentation: http://millejoh.github.io/emacs-ipython-notebook
.. _spacemacs layer: https://github.com/syl20bnr/spacemacs/tree/master/layers/%2Blang/ipython-notebook
.. _company-mode: https://github.com/company-mode/company-mode
.. _jupyterhub: https://github.com/jupyterhub/jupyterhub
.. _elpy: https://melpa.org/#/elpy
.. _program modes: https://www.gnu.org/software/emacs/manual/html_node/emacs/Program-Modes.html
.. _undo boundaries: https://www.gnu.org/software/emacs/manual/html_node/elisp/Undo.html

ob-ein
======
Configuration:

::

   M-x customize-group RET org-babel
   Org Babel Load Languages:
     Insert (ein . t)
     For example, '((emacs-lisp . t) (ein . t))

Snippet:

::

   #+BEGIN_SRC ein-python :session localhost
     import numpy, math, matplotlib.pyplot as plt
     %matplotlib inline
     x = numpy.linspace(0, 2*math.pi)
     plt.plot(x, numpy.sin(x))
   #+END_SRC

The ``:session`` is the notebook url, e.g., ``http://localhost:8888/my.ipynb``, or simply ``localhost``, in which case org evaluates anonymously.  A port may also be specified, e.g., ``localhost:8889``.

*Language* can be ``ein-python``, ``ein-r``, or ``ein-julia``.  **The relevant** `jupyter kernel`_ **must be installed before use**.  Additional languages can be configured via::

   M-x customize-group RET ein
   Ob Ein Languages

.. _polymode: https://github.com/polymode/polymode
.. _ob-ipython: https://github.com/gregsexton/ob-ipython
.. _scimax: https://github.com/jkitchin/scimax
.. _jupyter kernel: https://github.com/jupyter/jupyter/wiki/Jupyter-kernels

Amazon Web Services
===================
EIN has moved from GCE to AWS as the former's provisioning of GPUs appears stringent for customers without an established history.

From a notebook or raw ipynb buffer, ``M-x ein:gat-run-remote`` opens the notebook on an AWS spot instance.  You must ``M-x ein:stop`` or exit emacs to stop incurring charges!

``M-x ein:gat-run-remote-batch`` runs the notebook in `batch mode`_.

Results appear in the ``run-remote`` directory.

See `dickmao/Kaggler`_ for examples of importing Kaggle datasets.

See `gat usage`_ for information about the ``gat`` utility.

.. _gat utility: https://dickmaogat.readthedocs.io/en/latest/install.html
.. _gat usage: https://dickmaogat.readthedocs.io/en/latest/usage.html
.. _batch mode: https://nbconvert.readthedocs.io/en/latest/execute_api.html
.. _dickmao/Kaggler: https://github.com/dickmao/Kaggler/tree/gcspath#importing-datasets

Keymap (C-h m)
==============

::

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

   C-c M-w		ein:worksheet-copy-cell-km
