;; ein-process.el --- Notebook list buffer    -*- lexical-binding: t; -*-

;; Copyright (C) 2018- John M. Miller

;; Authors: Takafumi Arakaki <aka.tkf at gmail.com>
;;          John M. Miller <millejoh at mac.com>

;; This file is NOT part of GNU Emacs.

;; ein-process.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ein-process.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ein-process.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:


;;; Code:

(require 'ein-jupyter)

(defcustom ein:process-jupyter-regexp "\\(jupyter\\|ipython\\)\\(-\\|\\s-+\\)note"
  "Regexp by which we recognize notebook servers."
  :type 'string
  :group 'ein)

(defcustom ein:process-lsof "lsof"
  "Executable for lsof command."
  :type 'string
  :group 'ein)

(defun ein:process-divine-dir (pid args &optional error-buffer)
  "Returns notebook-dir or cwd of PID.  Supply ERROR-BUFFER to capture stderr"
  (if (string-match "\\bnotebook-dir\\(=\\|\\s-+\\)\\(\\S-+\\)" args)
      (directory-file-name (match-string 2 args))
    (when (executable-find ein:process-lsof)
      (ein:trim-right
       (with-output-to-string
         (shell-command (format "%s -p %d -a -d cwd -Fn | grep ^n | tail -c +2"
                                ein:process-lsof pid)
                        standard-output error-buffer))))))

(defun ein:process-divine-port (pid args &optional error-buffer)
  "Returns port on which PID is listening or 0 if none.  Supply ERROR-BUFFER to capture stderr"
  (if (string-match "\\bport\\(=\\|\\s-+\\)\\(\\S-+\\)" args)
      (string-to-number (match-string 2 args))
    (when (executable-find ein:process-lsof)
      (string-to-number
       (ein:trim-right
        (with-output-to-string
          (shell-command (format "%s -p %d -a -iTCP -sTCP:LISTEN -Fn | grep ^n | sed \"s/[^0-9]//g\""
                                 ein:process-lsof pid)
                         standard-output error-buffer)))))))

(defun ein:process-divine-ip (_pid args)
  "Returns notebook-ip of PID"
  (if (string-match "\\bip\\(=\\|\\s-+\\)\\(\\S-+\\)" args)
      (match-string 2 args)
    ein:url-localhost))

(cl-defstruct ein:$process
  "Hold process variables.

`ein:$process-pid' : integer
  PID.

`ein:$process-url': string
  URL

`ein:$process-dir' : string
  Arg of --notebook-dir or 'readlink -e /proc/<pid>/cwd'."
  pid
  url
  dir)

(ein:deflocal ein:%processes% (make-hash-table :test #'equal)
  "Process table of `ein:$process' keyed on dir.")

(defun ein:process-processes ()
  "Return list of processes."
  (hash-table-values ein:%processes%))

(defun ein:process-alive-p (proc)
  "Check if the PROC is still alive."
  (not (null (process-attributes (ein:$process-pid proc)))))

(defun ein:process-suitable-notebook-dir (filename)
  "Return the uppermost parent dir of DIR that contains ipynb files."
  (let ((fn (expand-file-name filename)))
    (cl-loop with directory = (directory-file-name
                            (if (file-regular-p fn)
                                (file-name-directory (directory-file-name fn))
                              fn))
          with suitable = directory
          until (string= (file-name-nondirectory directory) "")
          do (if (directory-files directory nil "\\.ipynb$")
                 (setq suitable directory))
          (setq directory (directory-file-name (file-name-directory directory)))
          finally return suitable)))

(defun ein:process-refresh-processes ()
  "Use `jupyter notebook list --json` to populate ein:%processes%"
  (clrhash ein:%processes%)
  (cl-loop for line in (condition-case err
                           (apply #'process-lines
                                  ein:jupyter-server-command
                                  (append (when ein:jupyter-server-use-subcommand
                                            (list ein:jupyter-server-use-subcommand))
                                          '("list" "--json")))
                         ;; often there is no local jupyter installation
                         (error (ein:log 'info "ein:process-refresh-processes: %s" err) nil))
           do (cl-destructuring-bind
                  (&key pid url notebook_dir &allow-other-keys)
                  (ein:json-read-from-string line)
                (when (and pid url)
                  (if notebook_dir
                      (puthash (directory-file-name notebook_dir)
                             (make-ein:$process :pid pid
                                                :url (ein:url url)
                                                :dir (directory-file-name notebook_dir))
                             ein:%processes%)
                    ;; For servers without notebook_dir (like JupyterHub)
                    (puthash "/" 
                             (make-ein:$process :pid pid
                                                :url (ein:url url)
                                                :dir "/")
                             ein:%processes%))))))

(defun ein:process-dir-match (filename)
  "Return ein:process whose directory is prefix of FILENAME."
  (cl-loop for dir in (hash-table-keys ein:%processes%)
        when (cl-search dir filename)
        return (gethash dir ein:%processes%)))

(defun ein:process-url-match (url-or-port)
  "Return ein:process whose url matches URL-OR-PORT."
  (cl-loop with parsed-url-or-port = (url-generic-parse-url url-or-port)
        for proc in (ein:process-processes)
        for parsed-url-proc = (url-generic-parse-url (ein:process-url-or-port proc))
        when (and (string= (url-host parsed-url-or-port) (url-host parsed-url-proc))
                  (= (url-port parsed-url-or-port) (url-port parsed-url-proc)))
        return proc))

(defsubst ein:process-url-or-port (proc)
  "Naively construct url-or-port from ein:process PROC's port and ip fields"
  (ein:$process-url proc))

(defsubst ein:process-path (proc filename)
  "Construct path by eliding PROC's dir from filename"
  (cl-subseq filename (length (file-name-as-directory (ein:$process-dir proc)))))

(defun ein:process-open-notebook* (filename callback)
  "Open FILENAME as a notebook and start a notebook server if necessary.  CALLBACK with arity 2 (passed into `ein:notebook-open--callback')."
  (ein:process-refresh-processes)
  (let* ((proc (ein:process-dir-match filename)))
    (if proc
        (let* ((url-or-port (ein:process-url-or-port proc))
               (path (ein:process-path proc filename))
               (callback2 (apply-partially (lambda (path* callback* _buffer url-or-port)
                                             (ein:notebook-open
                                              url-or-port path* nil callback*))
                                           path callback)))
          (if (ein:notebooklist-list-get url-or-port)
              (ein:notebook-open url-or-port path nil callback)
            (ein:notebooklist-login url-or-port callback2)))
      (let* ((nbdir (read-directory-name "Notebook directory: "
                                         (ein:process-suitable-notebook-dir filename)))
             (path
              (concat (if ein:jupyter-use-containers
                          (file-name-as-directory (file-name-base ein:jupyter-docker-mount-point))
                        "")
                      (cl-subseq (expand-file-name filename)
                                 (length (file-name-as-directory (expand-file-name nbdir))))))
             (callback2 (apply-partially (lambda (path* callback* buffer url-or-port)
                                           (pop-to-buffer buffer)
                                           (ein:notebook-open url-or-port
                                                              path* nil callback*))
                                         path callback)))
        (ein:jupyter-server-start (executable-find ein:jupyter-server-command)
                                  nbdir nil callback2)))))

(defun ein:process-open-notebook (&optional filename buffer-callback)
  "When FILENAME is unspecified the variable `buffer-file-name'
is used instead.  BUFFER-CALLBACK is called after notebook opened."
  (interactive)
  (unless filename (setq filename buffer-file-name))
  (cl-assert filename nil "Not visiting a file")
  (let ((callback2 (apply-partially (lambda (buffer buffer-callback* _notebook _created
                                                    &rest _args)
                                      (when (buffer-live-p buffer)
                                        (funcall buffer-callback* buffer)))
                                    (current-buffer) (or buffer-callback #'ignore))))
    (ein:process-open-notebook* (expand-file-name filename) callback2)))

(defun ein:process-find-file-callback ()
  "A callback function for `find-file-hook' to open notebook."
  (interactive)
  (-when-let* ((filename buffer-file-name)
               (match-p (string-match-p "\\.ipynb$" filename)))
    (ein:process-open-notebook filename #'kill-buffer-if-not-modified)))

(defcustom ein:notebook-default-home-directory nil
  "Default directory for Jupyter notebooks.
If set, this directory will be used as the Jupyter home directory
when opening notebooks. This solves path resolution issues when
the Jupyter server is started in a different directory than your notebooks.
If nil, EIN will try to determine the directory automatically."
  :type '(choice (const :tag "Auto" nil)
                 (directory :tag "Directory"))
  :group 'ein)

(defun ein:maybe-open-file-as-notebook ()
  (interactive)
  (when (eq major-mode 'ein:ipynb-mode)
    ;; More straightforward direct approach 
    (let* ((filename buffer-file-name)
           (home-dir (expand-file-name "~"))
           (url-or-port "http://127.0.0.1:8888")
           (expected-dir (or ein:notebook-default-home-directory home-dir))
           (rel-path nil)
           (log-buffer-name ein:log-all-buffer-name))
      
      ;; Debug logging
      (ein:log 'info "Notebook file: %s" filename)
      (ein:log 'info "Expected Jupyter dir: %s" expected-dir)
      
      ;; Calculate path relative to home directory
      (if (string-prefix-p expected-dir filename)
          (progn
            ;; Get path relative to home directory
            (setq rel-path (substring filename 
                                     (length (file-name-as-directory expected-dir))))
            (ein:log 'info "Using relative path: %s" rel-path))
        ;; Not in home dir, try code/notebooks subdirectory
        (let ((code-path (expand-file-name "code/notebooks" expected-dir)))
          (if (string-prefix-p code-path filename)
              (progn
                (setq rel-path (concat "code/notebooks/" 
                                      (file-name-nondirectory filename)))
                (ein:log 'info "Using code/notebooks/ path: %s" rel-path))
            ;; Just use filename as last resort
            (setq rel-path (file-name-nondirectory filename))
            (ein:log 'info "Using just filename: %s" rel-path))))
      
      ;; Try to open with calculated path
      (ein:log 'info "Opening notebook at %s with path: %s" url-or-port rel-path)
      (ein:notebook-open url-or-port rel-path nil 
                        (lambda (_notebook _created)
                          ;; Kill the original buffer
                          (when (buffer-live-p (current-buffer))
                            (kill-buffer-if-not-modified (current-buffer)))
                          ;; Kill the log buffer
                          (when (get-buffer log-buffer-name)
                            (kill-buffer log-buffer-name))
                          ;; Kill the Messages buffer as well
                          (when (get-buffer "*Messages*")
                            (let ((buf (get-buffer "*Messages*")))
                              (when (get-buffer-window buf)
                                (delete-window (get-buffer-window buf))))))))))

(provide 'ein-process)

;;; ein-process.el ends here