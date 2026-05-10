(in-package :chess-engine)

(defvar *acceptor* nil)
(defvar *current-state* (initial-board))

(defun handle-cors ()
  (setf (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
  (setf (hunchentoot:header-out "Access-Control-Allow-Methods") "GET, POST, OPTIONS")
  (setf (hunchentoot:header-out "Access-Control-Allow-Headers") "Content-Type, Accept"))

;; Top-level handlers
(hunchentoot:define-easy-handler (root-handler :uri "/") ()
  (hunchentoot:redirect "/index.html"))

(hunchentoot:define-easy-handler (state-handler :uri "/state") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (let ((state-alist (game-state-to-alist *current-state*)))
    (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
    (cl-json:encode-json-to-string state-alist)))
  
(hunchentoot:define-easy-handler (move-handler :uri "/move") (from to)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from move-handler ""))
    
  (if (and from to)
      (let* ((from-sq (parse-integer from))
             (to-sq (parse-integer to))
             (is-legal (member to-sq (legal-moves *current-state* from-sq))))
        (if is-legal
            (let ((san (move-to-san *current-state* from-sq to-sq))
                  (active (game-state-active-color *current-state*))
                  (fullmove (game-state-fullmove *current-state*)))
              (make-move *current-state* from-sq to-sq)
              (append-move-to-log san active fullmove)
              (let ((state-alist (game-state-to-alist *current-state*)))
                (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
                (cl-json:encode-json-to-string 
                 `((:success . t)
                   (:state . ,state-alist)))))
            (cl-json:encode-json-to-string '((:success . nil)))))
      (cl-json:encode-json-to-string '((:error . "Missing from or to parameters")))))
      
(hunchentoot:define-easy-handler (reset-handler :uri "/reset") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from reset-handler ""))
  (setf *current-state* (initial-board))
  (init-new-game-log)
  (let ((state-alist (game-state-to-alist *current-state*)))
    (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
    (cl-json:encode-json-to-string state-alist)))

(hunchentoot:define-easy-handler (legal-moves-handler :uri "/legal-moves") (sq)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (if sq
      (let* ((sq-num (parse-integer sq))
             (moves (legal-moves *current-state* sq-num)))
        (cl-json:encode-json-to-string `((:success . t) (:moves . ,moves))))
      (cl-json:encode-json-to-string '((:error . "Missing sq parameter")))))

(defun start-server (&key (port 8080))
  (when *acceptor*
    (hunchentoot:stop *acceptor*))
  
  ;; Reset dispatch table to avoid duplicates during restarts
  (setf hunchentoot:*dispatch-table* (list 'hunchentoot:dispatch-easy-handlers))
  
  (init-new-game-log)
  
  ;; Serve static files explicitly
  (push (hunchentoot:create-static-file-dispatcher-and-handler 
         "/index.html" (merge-pathnames "frontend/index.html" *default-pathname-defaults*))
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-static-file-dispatcher-and-handler 
         "/style.css" (merge-pathnames "frontend/style.css" *default-pathname-defaults*))
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-static-file-dispatcher-and-handler 
         "/main.js" (merge-pathnames "frontend/main.js" *default-pathname-defaults*))
        hunchentoot:*dispatch-table*)
        
  (setf *acceptor* (make-instance 'hunchentoot:easy-acceptor :port port))
  (hunchentoot:start *acceptor*)
  (format t "Chess engine server started on port ~A~%" port))

(defun stop-server ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*))
  (setf *acceptor* nil))
