;; ein-init.el - Configuration for Emacs IPython Notebook

;; Associate .ipynb files with ein:ipynb-mode
(add-to-list 'auto-mode-alist '("\\.ipynb\\'" . ein:ipynb-mode))

;; This helper will be used to create a simplified process entry
(defun my-ein-simplified-add-server (processes-hash url)
  "Add a simplified server entry to PROCESSES-HASH with URL."
  (puthash "/" 
           (list :pid -1 :url url :dir "/")
           processes-hash))

;; Setup function that runs when opening a notebook
(defun my-ein-ipynb-open ()
  "Open .ipynb files with EIN, using existing server."
  (when (and buffer-file-name 
             (string-match "\\.ipynb$" buffer-file-name))
    (let ((filename buffer-file-name))
      ;; Remove the JSON file buffer
      (kill-buffer)
      ;; Use a timer to ensure proper loading
      (run-with-timer 0.1 nil
                    (lambda (file)
                      ;; Reopen the file as notebook
                      (require 'ein)
                      (require 'ein-notebook)
                      
                      ;; Manually define our local server
                      (let ((server-url "http://127.0.0.1:8888"))
                        (message "EIN: Using Jupyter server at %s" server-url)
                        
                        ;; Start login and open process
                        (ein:notebooklist-login
                         server-url
                         (apply-partially 
                          (lambda (file* buffer url-or-port)
                            (with-current-buffer buffer
                              (ein:notebook-open url-or-port file* nil #'ignore)))
                          (file-name-nondirectory file)))))
                    filename))))

;; Add to find-file-hook to automatically handle .ipynb files
(add-hook 'find-file-hook #'my-ein-ipynb-open)

(provide 'ein-init)