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
  (cl-json:encode-json-to-string (game-state-to-alist *current-state*)))
  
(hunchentoot:define-easy-handler (move-handler :uri "/move") (from to)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from move-handler ""))
    
  (if (and from to)
      (let* ((from-sq (parse-integer from))
             (to-sq (parse-integer to))
             (success (make-move *current-state* from-sq to-sq)))
        (cl-json:encode-json-to-string 
         `((:success . ,(if success 't nil))
           (:state . ,(game-state-to-alist *current-state*)))))
      (cl-json:encode-json-to-string '((:error . "Missing from or to parameters")))))
      
(hunchentoot:define-easy-handler (reset-handler :uri "/reset") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from reset-handler ""))
  (setf *current-state* (initial-board))
  (cl-json:encode-json-to-string (game-state-to-alist *current-state*)))

(hunchentoot:define-easy-handler (legal-moves-handler :uri "/legal-moves") (sq)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (if sq
      (let* ((square (parse-integer sq))
             (moves (legal-moves *current-state* square)))
        (cl-json:encode-json-to-string `((:moves . ,moves))))
      (cl-json:encode-json-to-string '((:error . "Missing sq parameter")))))

(defun start-server (&key (port 8080))
  (when *acceptor*
    (hunchentoot:stop *acceptor*))
  
  ;; Reset dispatch table to avoid duplicates during restarts
  (setf hunchentoot:*dispatch-table* (list 'hunchentoot:dispatch-easy-handlers))
  
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
