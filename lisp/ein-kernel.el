;;; ein-kernel.el --- Communicate with IPython notebook server    -*- lexical-binding:t -*-

;; Copyright (C) 2012- Takafumi Arakaki

;; Author: Takafumi Arakaki <aka.tkf at gmail.com>

;; This file is NOT part of GNU Emacs.

;; ein-kernel.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ein-kernel.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ein-kernel.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; `ein:kernel' is the proxy class of notebook server state.
;; It agglomerates both the "kernel" and "session" objects of server described here
;; https://github.com/jupyter/jupyter/wiki/Jupyter-Notebook-Server-API
;; It may have been better to keep them separate to allow parallel reasoning with
;; the notebook server, but that time is past.

;;; Code:

(require 'ansi-color)

(require 'ein-core)
(require 'ein-classes)
(require 'ein-log)
(require 'ein-websocket)
(require 'ein-events)
(require 'ein-query)
(require 'ein-ipdb)

(declare-function ein:notebook-get-opened-notebook "ein-notebook")
(declare-function ein:notebooklist-get-buffer "ein-notebooklist")
(declare-function ein:notebooklist-reload "ein-notebooklist")

(defun ein:$kernel-session-url (kernel)
  (concat "/api/sessions/" (ein:$kernel-session-id kernel)))

;;;###autoload
(defalias 'ein:kernel-url-or-port 'ein:$kernel-url-or-port)

;;;###autoload
(defalias 'ein:kernel-id 'ein:$kernel-kernel-id)

(defcustom ein:pre-kernel-execute-functions nil
  "List of functions to call before sending a message to the kernel for execution. Each function is called with the message (see `ein:kernel--get-msg') about to be sent."
  :type 'list
  :group 'ein)

(defcustom ein:on-shell-reply-functions nil
  "List of functions to call when the kernel responds on the shell channel.
  Each function should have the call signature: msg-id header content metadata"
  :type 'list
  :group 'ein)

(defcustom ein:on-kernel-connect-functions nil
  "Abnormal hook that is run after a websocket connection is made
to a jupyter kernel. Functions defined here must accept a single
argument, which is the kernel that was just connected."
  :type 'list
  :group 'ein)


;;; Initialization and connection.

(defun ein:kernel-new (url-or-port path kernelspec base-url events &optional api-version)
  (make-ein:$kernel
   :url-or-port url-or-port
   :path path
   :kernelspec kernelspec
   :events events
   :api-version (or api-version 2)
   :session-id (ein:utils-uuid)
   :kernel-id nil
   :websocket nil
   :base-url base-url
   :stdin-activep nil
   :oinfo-cache (make-hash-table :test #'equal)
   :username "username"
   :msg-callbacks (make-hash-table :test 'equal)))


(defun ein:kernel-del (kernel)
  "Destructor for `ein:$kernel'."
  (ein:kernel-disconnect kernel))


(defun ein:kernel--get-msg (kernel msg-type content)
  (list
   :header (list
            :msg_id (ein:utils-uuid)
            :username (ein:$kernel-username kernel)
            :session (ein:$kernel-session-id kernel)
            :version "5.0"
            :date (format-time-string "%Y-%m-%dT%T" (current-time)) ; ISO 8601 timestamp
            :msg_type msg-type)
   :metadata (make-hash-table)
   :content content
   :parent_header (make-hash-table)))

(cl-defun ein:kernel-session-p (kernel callback &optional iteration)
  "Don't make any changes on the server side.  CALLBACK with arity 2, kernel and a boolean whether session exists on server."
  (unless iteration
    (setq iteration 0))
  (let ((session-id (ein:$kernel-session-id kernel)))
    (ein:query-singleton-ajax
     (ein:url (ein:$kernel-url-or-port kernel) "api/sessions" session-id)
     :type "GET"
     :parser #'ein:json-read
     :complete (apply-partially #'ein:kernel-session-p--complete session-id)
     :success (apply-partially #'ein:kernel-session-p--success kernel session-id callback)
     :error (apply-partially #'ein:kernel-session-p--error kernel callback iteration))))

(cl-defun ein:kernel-session-p--complete (_session-id
                                          &key data response
                                          &allow-other-keys
                                          &aux (resp-string (format "STATUS: %s DATA: %s" (request-response-status-code response) data)))
  (ein:log 'debug "ein:kernel-session-p--complete %s" resp-string))

(cl-defun ein:kernel-session-p--error (kernel callback iteration
                                       &key error-thrown _symbol-status data
                                       &allow-other-keys)
  (if (ein:aand (plist-get data :message) (cl-search "not found" it))
      (when callback (funcall callback kernel nil))
    (let* ((max-tries 3)
           (tries-left (1- (- max-tries iteration))))
      (ein:log 'verbose "ein:kernel-session-p--error [%s], %s tries left"
               (car error-thrown) tries-left)
      (if (> tries-left 0)
          (ein:kernel-session-p kernel callback (1+ iteration))))))

(cl-defun ein:kernel-session-p--success (kernel session-id callback
                                         &key data &allow-other-keys)
  (let ((session-p (equal (plist-get data :id) session-id)))
    (ein:log 'verbose "ein:kernel-session-p--success: session-id=%s session-p=%s"
             session-id session-p)
    (when callback (funcall callback kernel session-p))))

(cl-defun ein:kernel-restart-session (kernel)
  "Server side delete of KERNEL session and subsequent restart with all new state"
  (ein:kernel-delete-session
   (lambda (kernel)
     (ein:events-trigger (ein:$kernel-events kernel) 'status_restarting.Kernel)
     (ein:kernel-retrieve-session kernel 0
                                  (lambda (kernel)
                                    (ein:events-trigger (ein:$kernel-events kernel)
                                                        'status_restarted.Kernel))))
   :kernel kernel))

(cl-defun ein:kernel-retrieve-session (kernel &optional iteration callback)
  "Formerly ein:kernel-start, but that was misnomer because 1. the server really starts a session (and an accompanying kernel), and 2. it may not even start a session if one exists for the same path.

If 'picking up from where we last left off', that is, we restart emacs and reconnect to same server, jupyter will hand us back the original, still running session.

The server logic is here (could not find other documentation)
https://github.com/jupyter/notebook/blob/04a686dbaf9dfe553324a03cb9e6f778cf1e3da1/notebook/services/sessions/handlers.py#L56-L81

CALLBACK of arity 1, the kernel.
"
  (unless iteration
    (setq iteration 0))
  (let ((kernel-id (ein:$kernel-kernel-id kernel))
        (kernelspec (ein:$kernel-kernelspec kernel))
        (path (ein:$kernel-path kernel)))
      (ein:query-singleton-ajax
       (ein:url (ein:$kernel-url-or-port kernel) "api/sessions")
       :type "POST"
       :data (ein:json-encode
              `((path . ,path)
                (type . "notebook")
                ,@(if kernelspec
                      `((kernel .
                                ((name . ,(ein:$kernelspec-name kernelspec))
                                 ,@(if kernel-id
                                       `((id . ,kernel-id)))))))))
       :parser #'ein:json-read
       :complete (apply-partially #'ein:kernel-retrieve-session--complete kernel callback)
       :success (apply-partially #'ein:kernel-retrieve-session--success kernel callback)
       :error (apply-partially #'ein:kernel-retrieve-session--error kernel iteration callback))))

(cl-defun ein:kernel-retrieve-session--complete
    (_kernel _callback
     &key data response
     &allow-other-keys
     &aux (resp-string (format "STATUS: %s DATA: %s" (request-response-status-code response) data)))
  (ein:log 'debug "ein:kernel-retrieve-session--complete %s" resp-string))

(cl-defun ein:kernel-retrieve-session--error
    (kernel iteration callback
     &key error-thrown _symbol-status &allow-other-keys)
  (let* ((max-tries 3)
         (tries-left (1- (- max-tries iteration))))
    (ein:log 'verbose "ein:kernel-retrieve-session--error [%s], %s tries left"
             (car error-thrown) tries-left)
    (sleep-for 0 (* (1+ iteration) 500))
    (if (> tries-left 0)
        (ein:kernel-retrieve-session kernel (1+ iteration) callback))))

(cl-defun ein:kernel-retrieve-session--success (kernel callback &key data &allow-other-keys)
  (let ((session-id (plist-get data :id)))
    (if (plist-get data :kernel)
        (setq data (plist-get data :kernel)))
    (cl-destructuring-bind (&key id &allow-other-keys) data
      (ein:log 'verbose "ein:kernel-retrieve-session--success: kernel-id=%s session-id=%s"
               id session-id)
      (setf (ein:$kernel-kernel-id kernel) id)
      (setf (ein:$kernel-session-id kernel) session-id)
      (setf (ein:$kernel-ws-url kernel) (ein:kernel--ws-url (ein:$kernel-url-or-port kernel)))
      (setf (ein:$kernel-kernel-url kernel)
            (concat (file-name-as-directory (ein:$kernel-base-url kernel)) id))
      ;; Make sure we set either shell-channel or websocket to handle all channels
      (if (= (ein:$kernel-api-version kernel) 2)
          (setf (ein:$kernel-shell-channel kernel) nil)
        (setf (ein:$kernel-shell-channel kernel) t)))
    (ein:kernel-start-websocket kernel callback)))

(defun ein:kernel-reconnect-session (kernel &optional callback)
  "Check if session still exists.  If it does, retrieve it.  If it doesn't, ask the user to create a new session (ein:kernel-retrieve-session both retrieves and creates).

CALLBACK takes one argument kernel (e.g., execute cell now that we're reconnected)"
  (ein:kernel-disconnect kernel)
  (ein:kernel-session-p
   kernel
   (apply-partially
    (lambda (callback* kernel session-p)
      (when (or session-p
                (and (not noninteractive) (y-or-n-p "Session not found.  Restart?")))
        (ein:events-trigger (ein:$kernel-events kernel) 'status_reconnecting.Kernel)
        (ein:kernel-retrieve-session
         kernel 0
         (apply-partially
          (lambda (callback** kernel)
            (ein:events-trigger (ein:$kernel-events kernel)
                                'status_reconnected.Kernel)
            (when callback** (funcall callback** kernel)))
          callback*))))
    callback)))

(defun ein:kernel--ws-url (url-or-port)
  "Assuming URL-OR-PORT already normalized by `ein:url'.
See https://github.com/ipython/ipython/pull/3307"
  (let* ((parsed-url (url-generic-parse-url url-or-port))
         (protocol (if (string= (url-type parsed-url) "https") "wss" "ws")))
    (format "%s://%s:%s%s"
            protocol
            (url-host parsed-url)
            (url-port parsed-url)
            (url-filename parsed-url))))

(defun ein:kernel--handle-websocket-reply (kernel _ws frame)
  (-when-let* ((packet (websocket-frame-payload frame))
               (channel (plist-get (ein:json-read-from-string packet) :channel)))
    (cond ((string-equal channel "iopub")
           (ein:kernel--handle-iopub-reply kernel packet))
          ((string-equal channel "shell")
           (ein:kernel--handle-shell-reply kernel packet))
          ((string-equal channel "stdin")
           (ein:kernel--handle-stdin-reply kernel packet))
          (t (ein:log 'warn "Received reply from unforeseen channel %s" channel)))))

(defun ein:start-single-websocket (kernel open-callback)
  "OPEN-CALLBACK (kernel) (e.g., execute cell)"
  (let ((ws-url (concat (ein:$kernel-ws-url kernel)
                         (ein:$kernel-kernel-url kernel)
                         "/channels?session_id="
                         (ein:$kernel-session-id kernel))))
    (ein:log 'verbose "WS start: %s" ws-url)
    (setf (ein:$kernel-websocket kernel)
          (ein:websocket ws-url kernel
                         (apply-partially #'ein:kernel--handle-websocket-reply kernel)
                         (lambda (ws)
                           (-if-let* ((websocket (websocket-client-data ws))
                                      (kernel (ein:$websocket-kernel websocket)))
                               (unless (ein:$websocket-closed-by-client websocket)
                                 (ein:log 'verbose "WS closed unexpectedly: %s" (websocket-url ws))
                                 (ein:kernel-disconnect kernel))
                             (ein:log 'error "ein:start-single-websocket: on-close no client data for %s." (websocket-url ws))))
                         (apply-partially
                          (lambda (cb ws)
                            (-if-let* ((websocket (websocket-client-data ws))
                                       (kernel (ein:$websocket-kernel websocket)))
                                (progn
                                  (when (ein:kernel-live-p kernel)
                                    (run-hook-with-args 'ein:on-kernel-connect-functions kernel)
                                    (when cb (funcall cb kernel)))
                                  (ein:log 'verbose "WS opened: %s" (websocket-url ws)))
                              (ein:log 'error "ein:start-single-websocket: on-open no client data for %s." (websocket-url ws))))
                          open-callback)))))

(defun ein:kernel-start-websocket (kernel callback)
  (ein:start-single-websocket kernel callback))

(defun ein:kernel-on-connect (_kernel _content _metadata)
  (ein:log 'info "Kernel connect_request_reply received."))

(defun ein:kernel-disconnect (kernel)
  "Close websocket connection to running kernel, but do not
delete the kernel on the server side"
  (ein:events-trigger (ein:$kernel-events kernel) 'status_disconnected.Kernel)
  (aif (ein:$kernel-websocket kernel)
      (progn (ein:websocket-close it)
             (setf (ein:$kernel-websocket kernel) nil))))

(defun ein:kernel-live-p (kernel)
  (and (ein:$kernel-p kernel)
       (ein:$kernel-websocket kernel)
       (ein:websocket-open-p (ein:$kernel-websocket kernel))))

(defun ein:kernel-when-ready (kernel callback)
  "Execute CALLBACK of arity 1 (the kernel) when KERNEL is ready.  Warn user otherwise."
  (if (ein:kernel-live-p kernel)
      (funcall callback kernel)
    (ein:log 'verbose "Kernel %s unavailable" (ein:$kernel-kernel-id kernel))
    (ein:kernel-reconnect-session kernel callback)))

(defun ein:kernel-object-info-request (kernel objname callbacks &optional cursor-pos detail-level)
  "Send object info request of OBJNAME to KERNEL.

When calling this method pass a CALLBACKS structure of the form:

    (:object_info_reply (FUNCTION . ARGUMENT))

Call signature::

  (`funcall' FUNCTION ARGUMENT CONTENT METADATA)

CONTENT and METADATA are given by `object_info_reply' message.

`object_info_reply' message is documented here:
http://ipython.org/ipython-doc/dev/development/messaging.html#object-information
"
  (cl-assert (ein:kernel-live-p kernel) nil "object_info_reply: Kernel is not active.")
  (when objname
    (let* ((content (if (< (ein:$kernel-api-version kernel) 5)
                        (list
                         ;; :text ""
                         :oname (format "%s" objname)
                         :cursor_pos (or cursor-pos 0)
                         :detail_level (or detail-level 0))
                      (list
                       :code (format "%s" objname)
                       :cursor_pos (or cursor-pos 0)
                       :detail_level (or detail-level 0))))
           (msg (ein:kernel--get-msg kernel "inspect_request"
                                     (append content (list :detail_level 1))))
           (msg-id (plist-get (plist-get msg :header) :msg_id)))
      (ein:websocket-send-shell-channel kernel msg)
      (ein:kernel-set-callbacks-for-msg kernel msg-id callbacks))))

(cl-defun ein:kernel-execute (kernel code &optional callbacks
                              &key
                              (silent t)
                              (store-history t)
                              (user-expressions (make-hash-table))
                              (allow-stdin t)
                              (stop-on-error nil))
  "Execute CODE on KERNEL.

The CALLBACKS plist looks like:

  (:execute_reply  EXECUTE-REPLY-CALLBACK
   :output         OUTPUT-CALLBACK
   :clear_output   CLEAR-OUTPUT-CALLBACK
   :set_next_input SET-NEXT-INPUT)

Right hand sides ending -CALLBACK above are of the form (FUNCTION ARG1 ... ARGN).
(Hindsight: this was all much better implemented using `apply-partially')

Return randomly generated MSG-ID tag uniquely identifying expectation of a kernel response.
"
  (cl-assert (ein:kernel-live-p kernel) nil "execute_reply: Kernel is not active.")
  (let* ((content (list
                   :code code
                   :silent (or silent json-false)
                   :store_history (or store-history json-false)
                   :user_expressions user-expressions
                   :allow_stdin allow-stdin
                   :stop_on_error (or stop-on-error json-false)))
         (msg (ein:kernel--get-msg kernel "execute_request" content))
         (msg-id (plist-get (plist-get msg :header) :msg_id)))
    (ein:log 'debug "ein:kernel-execute: code=%s msg_id=%s" code msg-id)
    (run-hook-with-args 'ein:pre-kernel-execute-functions msg)
    (ein:websocket-send-shell-channel kernel msg)
    (ein:kernel-set-callbacks-for-msg kernel msg-id callbacks)
    (unless silent
      (mapc #'ein:funcall-packed
            (ein:$kernel-after-execute-hook kernel)))
    msg-id))

(defun ein:kernel-complete (kernel line cursor-pos callbacks errback)
  "Complete code at CURSOR-POS in a string LINE on KERNEL.

CURSOR-POS is the position in the string LINE, not in the buffer.

ERRBACK takes a string (error message).

When calling this method pass a CALLBACKS structure of the form:

    (:complete_reply (FUNCTION . ARGUMENT))

Call signature::

  (funcall FUNCTION ARGUMENT CONTENT METADATA)

CONTENT and METADATA are given by `complete_reply' message.

`complete_reply' message is documented here:
http://ipython.org/ipython-doc/dev/development/messaging.html#complete
"
  (condition-case err
      (let* ((content (if (< (ein:$kernel-api-version kernel) 4)
                          (list
                           ;; :text ""
                           :line line
                           :cursor_pos cursor-pos)
                        (list
                         :code line
                         :cursor_pos cursor-pos)))
             (msg (ein:kernel--get-msg kernel "complete_request" content))
             (msg-id (plist-get (plist-get msg :header) :msg_id)))
        (cl-assert (ein:kernel-live-p kernel) nil "kernel not live")
        (ein:websocket-send-shell-channel kernel msg)
        (ein:kernel-set-callbacks-for-msg kernel msg-id callbacks)
        msg-id)
    (error (if errback (funcall errback (error-message-string err))
             (ein:display-warning (error-message-string err) :error)))))


(cl-defun ein:kernel-history-request (kernel callbacks
                                      &key
                                      (output nil)
                                      (raw t)
                                      (hist-access-type "tail")
                                      session
                                      start
                                      stop
                                      (n 10)
                                      pattern
                                      unique)
  "Request execution history to KERNEL.

When calling this method pass a CALLBACKS structure of the form:

    (:history_reply (FUNCTION . ARGUMENT))

Call signature::

  (`funcall' FUNCTION ARGUMENT CONTENT METADATA)

CONTENT and METADATA are given by `history_reply' message.

`history_reply' message is documented here:
http://ipython.org/ipython-doc/dev/development/messaging.html#history

Relevant Python code:

* :py:method:`IPython.zmq.ipkernel.Kernel.history_request`
* :py:class:`IPython.core.history.HistoryAccessor`
"
  (cl-assert (ein:kernel-live-p kernel) nil "history_reply: Kernel is not active.")
  (let* ((content (list
                   :output (ein:json-any-to-bool output)
                   :raw (ein:json-any-to-bool raw)
                   :hist_access_type hist-access-type
                   :session session
                   :start start
                   :stop stop
                   :n n
                   :pattern pattern
                   :unique unique))
         (msg (ein:kernel--get-msg kernel "history_request" content))
         (msg-id (plist-get (plist-get msg :header) :msg_id)))
    (ein:websocket-send-shell-channel kernel msg)
    (ein:kernel-set-callbacks-for-msg kernel msg-id callbacks)
    msg-id))

(defun ein:kernel-connect-request (kernel callbacks)
  "Request basic information for a KERNEL.

When calling this method pass a CALLBACKS structure of the form::

  (:connect_reply (FUNCTION . ARGUMENT))

Call signature::

  (`funcall' FUNCTION ARGUMENT CONTENT METADATA)

CONTENT and METADATA are given by `kernel_info_reply' message.

`connect_request' message is documented here:
http://ipython.org/ipython-doc/dev/development/messaging.html#connect

Example::

  (ein:kernel-connect-request
   (ein:get-kernel)
   '(:kernel_connect_reply (message . \"CONTENT: %S\\nMETADATA: %S\")))
"
  ;(cl-assert (ein:kernel-live-p kernel) nil "connect_reply: Kernel is not active.")
  (let* ((msg (ein:kernel--get-msg kernel "connect_request" (make-hash-table)))
         (msg-id (plist-get (plist-get msg :header) :msg_id)))
    (ein:websocket-send-shell-channel kernel msg)
    (ein:kernel-set-callbacks-for-msg kernel msg-id callbacks)
    msg-id))

(defun ein:kernel-interrupt (kernel)
  (when (ein:kernel-live-p kernel)
    (ein:log 'info "Interrupting kernel")
    (ein:query-singleton-ajax
     (ein:url (ein:$kernel-url-or-port kernel)
              (ein:$kernel-kernel-url kernel)
              "interrupt")
     :type "POST"
     :success (lambda (&rest _ignore)
                (ein:log 'info "Sent interruption command.")))))

(defvar ein:force-sync)
(declare-function ein:content-query-sessions "ein-contents-api")
(cl-defun ein:kernel-delete-session (&optional callback
                                     &key url-or-port path kernel
                                     &aux (session-id))
  "Regardless of success or error, we clear all state variables of kernel and funcall CALLBACK (kernel)"
  (cond (kernel
         (setq url-or-port (ein:$kernel-url-or-port kernel))
         (setq path (ein:$kernel-path kernel))
         (setq session-id (ein:$kernel-session-id kernel)))
        ((and url-or-port path)
         (aif (ein:notebook-get-opened-notebook url-or-port path)
             (progn
               (setq kernel (ein:$notebook-kernel it))
               (setq session-id (ein:$kernel-session-id kernel)))
           (let ((ein:force-sync t))
             (ein:content-query-sessions
              url-or-port
              (lambda (session-hash)
                (setq session-id (car (gethash path session-hash))))
              nil))))
        (t (error "ein:kernel-delete-session: need kernel, or url-or-port and path")))
  (if session-id
      (ein:query-singleton-ajax
       (ein:url url-or-port "api/sessions" session-id)
       :type "DELETE"
       :complete (apply-partially #'ein:kernel-delete-session--complete kernel session-id callback)
       :error (apply-partially #'ein:kernel-delete-session--error session-id nil)
       :success (apply-partially #'ein:kernel-delete-session--success session-id
                                 (aif (ein:notebooklist-get-buffer url-or-port)
                                     (buffer-local-value 'ein:%notebooklist% it))
                                 nil))
    (ein:log 'verbose "ein:kernel-delete-session: no sessions found for %s" path)
    (when callback
      (funcall callback kernel))))

(cl-defun ein:kernel-delete-session--error (session-id _callback
                                            &key _response error-thrown
                                            &allow-other-keys)
  (ein:log 'error "ein:kernel-delete-session--error %s: ERROR %s DATA %s"
           session-id (car error-thrown) (cdr error-thrown)))

(cl-defun ein:kernel-delete-session--success (session-id nblist _callback
                                              &key _data _symbol-status _response
                                              &allow-other-keys)
  (ein:log 'verbose "ein:kernel-delete-session--success: %s deleted" session-id)
  (when nblist
    (ein:notebooklist-reload nblist)))

(cl-defun ein:kernel-delete-session--complete (kernel _session-id callback
                                               &key data response
                                               &allow-other-keys
                                               &aux (resp-string (format "STATUS: %s DATA: %s" (request-response-status-code response) data)))
  (ein:log 'verbose "ein:kernel-delete-session--complete %s" resp-string)
  (when kernel
    (ein:kernel-disconnect kernel))
  (when callback (funcall callback kernel)))

;; Reply handlers.
(defun ein:kernel-get-callbacks-for-msg (kernel msg-id)
  (gethash msg-id (ein:$kernel-msg-callbacks kernel)))

(defun ein:kernel-set-callbacks-for-msg (kernel msg-id callbacks)
  "Set up promise for MSG-ID."
  (puthash msg-id callbacks (ein:$kernel-msg-callbacks kernel)))

(defun ein:kernel--handle-stdin-reply (kernel packet)
  (setf (ein:$kernel-stdin-activep kernel) t)
  (cl-destructuring-bind
      (&key header _parent_header _metadata content &allow-other-keys)
      (ein:json-read-from-string packet)
    (let ((msg-type (plist-get header :msg_type))
          (msg-id (plist-get header :msg_id))
          (password (plist-get content :password)))
      (ein:log 'debug "ein:kernel--handle-stdin-reply: msg_type=%s msg_id=%s"
               msg-type msg-id)
      (cond ((string-equal msg-type "input_request")
             (if (not (eql password :json-false))
                 (let* ((passwd (read-passwd (plist-get content :prompt)))
                        (content (list :value passwd))
                        (msg (ein:kernel--get-msg kernel "input_reply" content)))
                   (ein:websocket-send-stdin-channel kernel msg)
                   (setf (ein:$kernel-stdin-activep kernel) nil))
               (cond ((string-match "ipdb>" (plist-get content :prompt)) (ein:run-ipdb-session kernel "ipdb> "))
                     ((string-match "(Pdb)" (plist-get content :prompt)) (ein:run-ipdb-session kernel "(Pdb) "))
                     (t (let* ((in (read-string (plist-get content :prompt)))
                               (content (list :value in))
                               (msg (ein:kernel--get-msg kernel "input_reply" content)))
                          (ein:websocket-send-stdin-channel kernel msg)
                          (setf (ein:$kernel-stdin-activep kernel) nil))))))))))

(defun ein:kernel--handle-payload (kernel callbacks payload)
  (cl-loop with events = (ein:$kernel-events kernel)
        for p in payload
        for text = (or (plist-get p :text) (plist-get (plist-get p :data) :text/plain))
        for source = (plist-get p :source)
        if (member source '("IPython.kernel.zmq.page.page"
                            "IPython.zmq.page.page"
                            "page"))
        do (when (not (equal (ein:trim text) ""))
             (ein:events-trigger
              events 'open_with_text.Pager (list :text text)))
        else if
        (member
         source
         '("IPython.kernel.zmq.zmqshell.ZMQInteractiveShell.set_next_input"
           "IPython.zmq.zmqshell.ZMQInteractiveShell.set_next_input"
           "set_next_input"))
        do (let ((cb (plist-get callbacks :set_next_input)))
             (when cb (ein:funcall-packed cb text)))))

(defun ein:kernel--handle-shell-reply (kernel packet)
  (cl-destructuring-bind
      (&key header content metadata parent_header &allow-other-keys)
      (ein:json-read-from-string packet)
    (let* ((msg-type (plist-get header :msg_type))
           (msg-id (plist-get parent_header :msg_id))
           (callbacks (ein:kernel-get-callbacks-for-msg kernel msg-id)))
      (ein:log 'debug "ein:kernel--handle-shell-reply: msg_type=%s msg_id=%s"
               msg-type msg-id)
      (run-hook-with-args 'ein:on-shell-reply-functions msg-type header content metadata)
      (aif (plist-get callbacks (intern-soft (format ":%s" msg-type)))
          (ein:funcall-packed it content metadata)
        (ein:log 'info "ein:kernel--handle-shell-reply: No :%s callback for msg_id=%s"
                 msg-type msg-id))
      (aif (plist-get content :payload)
          (ein:kernel--handle-payload kernel callbacks it))
      (let ((events (ein:$kernel-events kernel)))
        (ein:case-equal msg-type
          (("execute_reply")
           (aif (plist-get content :execution_count)
               (ein:events-trigger events 'execution_count.Kernel it))))))))

(defun ein:kernel--handle-iopub-reply (kernel packet)
  (if (ein:$kernel-stdin-activep kernel)
      (ein:ipdb--handle-iopub-reply kernel packet)
    (cl-destructuring-bind
        (&key content metadata parent_header header &allow-other-keys)
        (ein:json-read-from-string packet)
      (let* ((msg-type (plist-get header :msg_type))
             (msg-id (plist-get header :msg_id))
             (parent-id (plist-get parent_header :msg_id))
             (callbacks (ein:kernel-get-callbacks-for-msg kernel parent-id))
             (events (ein:$kernel-events kernel)))
        (ein:log 'debug
          "ein:kernel--handle-iopub-reply: msg_type=%s msg_id=%s parent_id=%s"
          msg-type msg-id parent-id)
        (ein:case-equal msg-type
          (("stream" "display_data" "pyout" "pyerr" "error" "execute_result")
           (aif (plist-get callbacks :output) ;; ein:cell--handle-output
               (ein:funcall-packed it msg-type content metadata)
             (ein:log 'warn (concat "ein:kernel--handle-iopub-reply: "
                                    "No :output callback for parent_id=%s")
                      parent-id)))
          (("status")
           (ein:case-equal (plist-get content :execution_state)
             (("busy")
              (ein:events-trigger events 'status_busy.Kernel))
             (("idle")
              (ein:events-trigger events 'status_idle.Kernel))
             (("dead")
              (ein:kernel-disconnect kernel))))
          (("data_pub")
           (ein:log 'verbose "ein:kernel--handle-iopub-reply: data_pub %S" packet))
          (("clear_output")
           (aif (plist-get callbacks :clear_output)
               (ein:funcall-packed it content metadata)
             (ein:log 'info (concat "ein:kernel--handle-iopub-reply: "
                                    "No :clear_output callback for parent_id=%s")
                      parent-id))))))))

(provide 'ein-kernel)

;;; ein-kernel.el ends here
