(in-package :chess-engine)

(defvar *acceptor* nil)
(defvar *current-state* (initial-board))
(defvar *state-history* nil)
(defvar *current-game-moves* nil) ; List of (from to)
(defvar *current-pgn-collection* nil) ; List of (:headers ... :moves ...)

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
            (let ((san "move")
                  (active (game-state-active-color *current-state*))
                  (fullmove (game-state-fullmove *current-state*))
                  (old-state (copy-state *current-state*)))
              (make-move *current-state* from-sq to-sq)
              (push old-state *state-history*)
              ;; (append-move-to-log san active fullmove)
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
  (setf *state-history* nil)
  ;; (init-new-game-log)
  (let ((state-alist (game-state-to-alist *current-state*)))
    (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
    (cl-json:encode-json-to-string state-alist)))

(hunchentoot:define-easy-handler (undo-handler :uri "/undo") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from undo-handler ""))
  
  (when *state-history*
    (setf *current-state* (pop *state-history*)))
    
  (let ((state-alist (game-state-to-alist *current-state*)))
    (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
    (cl-json:encode-json-to-string `((:success . t) (:state . ,state-alist)))))
;; Mode management endpoints
(hunchentoot:define-easy-handler (set-mode-handler :uri "/set-mode") (mode)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from set-mode-handler ""))
  (cond ((string= mode "game")
         (setf *game-mode* :game))
        ((string= mode "explore")
         (setf *game-mode* :explore))
        (t (return-from set-mode-handler
             (cl-json:encode-json-to-string '((:error . "Invalid mode"))))))
  (cl-json:encode-json-to-string `((:success . t) (:mode . ,(string-downcase (symbol-name *game-mode*))))))

;; Place a piece at a specific square (explore mode only)
(hunchentoot:define-easy-handler (place-piece-handler :uri "/place-piece") (sq color type)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from place-piece-handler ""))
  (if (eq *game-mode* :explore)
      (let ((sq-num (parse-integer sq))
            (piece-color (if (string= (string-downcase color) "white") :white :black))
            (piece-type (case (string-downcase type)
                          ("pawn" :pawn)
                          ("knight" :knight)
                          ("bishop" :bishop)
                          ("rook" :rook)
                          ("queen" :queen)
                          ("king" :king)
                          (t nil))))
        (if piece-type
            (progn
              (setf (aref (game-state-board *current-state*) sq-num)
                    (make-piece :color piece-color :type piece-type))
              (cl-json:encode-json-to-string '((:success . t))))
            (cl-json:encode-json-to-string '((:error . "Invalid piece type")))))
      (cl-json:encode-json-to-string '((:error . "Not in explore mode")))))

;; Remove a piece from a square (explore mode only)
(hunchentoot:define-easy-handler (remove-piece-handler :uri "/remove-piece") (sq)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from remove-piece-handler ""))
  (if (eq *game-mode* :explore)
      (let ((sq-num (parse-integer sq)))
        (setf (aref (game-state-board *current-state*) sq-num) nil)
        (cl-json:encode-json-to-string '((:success . t))))
      (cl-json:encode-json-to-string '((:error . "Not in explore mode")))))

;; Clear board (explore mode only)
(hunchentoot:define-easy-handler (clear-board-handler :uri "/clear-board") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from clear-board-handler ""))
  (if (eq *game-mode* :explore)
      (progn
        (setf (game-state-board *current-state*) (make-array 64 :initial-element nil))
        (cl-json:encode-json-to-string '((:success . t))))
      (cl-json:encode-json-to-string '((:error . "Not in explore mode")))))


(hunchentoot:define-easy-handler (move-piece-explore-handler :uri "/move-piece-explore") (from to)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from move-piece-explore-handler ""))
  (if (and from to)
      (let ((from-sq (parse-integer from))
            (to-sq (parse-integer to)))
        (if (and (eq *game-mode* :explore) (>= from-sq 0) (< from-sq 64) (>= to-sq 0) (< to-sq 64))
            (let ((piece (aref (game-state-board *current-state*) from-sq)))
              (setf (aref (game-state-board *current-state*) from-sq) nil)
              (setf (aref (game-state-board *current-state*) to-sq) piece)
              (cl-json:encode-json-to-string '((:success . t))))
            (cl-json:encode-json-to-string '((:error . "Not in explore mode or out of bounds")))))
      (cl-json:encode-json-to-string '((:error . "Missing from or to parameters")))))

(hunchentoot:define-easy-handler (load-pgn-handler :uri "/load-pgn") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((raw-body (hunchentoot:raw-post-data :force-text t))
         (collection (parse-pgn-collection raw-body)))
    (setf *current-pgn-collection* collection)
    (setf *current-game-moves* nil)
    (cl-json:encode-json-to-string 
     `((:success . t) 
       (:games . ,(loop for game in collection 
                        for i from 0
                        collect `((:index . ,i) 
                                  (:headers . ,(cdr (assoc :headers game))))))))))

(hunchentoot:define-easy-handler (select-game-handler :uri "/select-game") (index)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((idx (parse-integer index))
         (game (nth idx *current-pgn-collection*)))
    (if game
        (progn
          (setf *current-game-moves* (cdr (assoc :moves game)))
          (setf *current-state* (initial-board))
          (cl-json:encode-json-to-string `((:success . t) (:moveCount . ,(length *current-game-moves*)))))
        (cl-json:encode-json-to-string '((:error . "Invalid game index"))))))

(hunchentoot:define-easy-handler (game-move-handler :uri "/game-move") (index)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (let ((idx (parse-integer index)))
    (if (and *current-game-moves* (>= idx 0) (< idx (length *current-game-moves*)))
        (let* ((move (nth idx *current-game-moves*))
               (from (first move))
               (to (second move)))
          ;; Apply move to *current-state*
          (let ((piece (aref (game-state-board *current-state*) from)))
            (setf (aref (game-state-board *current-state*) from) nil)
            (setf (aref (game-state-board *current-state*) to) piece)
            (setf (game-state-active-color *current-state*) 
                  (if (eq (game-state-active-color *current-state*) :white) :black :white)))
          (cl-json:encode-json-to-string `((:success . t) (:state . ,(game-state-to-alist *current-state*)))))
        (cl-json:encode-json-to-string '((:error . "Invalid move index"))))))

(hunchentoot:define-easy-handler (load-fen-handler :uri "/load-fen") (fen)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (when (eq (hunchentoot:request-method*) :options)
    (return-from load-fen-handler ""))
  (if fen
      (progn
        (setf *current-state* (parse-fen fen))
        (setf *state-history* nil)
        (let ((state-alist (game-state-to-alist *current-state*)))
          (push `(:status . ,(string-downcase (symbol-name (get-game-status *current-state*)))) state-alist)
          (cl-json:encode-json-to-string `((:success . t) (:state . ,state-alist)))))
      (cl-json:encode-json-to-string '((:error . "Missing fen parameter")))))

(hunchentoot:define-easy-handler (legal-moves-handler :uri "/legal-moves") (sq)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (if sq
      (let* ((sq-num (parse-integer sq))
             (moves (legal-moves *current-state* sq-num)))
        (cl-json:encode-json-to-string `((:success . t) (:moves . ,moves))))
      (cl-json:encode-json-to-string '((:error . "Missing sq parameter")))))

(hunchentoot:define-easy-handler (analyze-handler :uri "/analyze") (fen)
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (let* ((target-fen (or fen (generate-fen *current-state*)))
         (result (analyze-position target-fen)))
    (cl-json:encode-json-to-string 
     `((:success . t)
       (:score . ,(getf result :score))
       (:bestMove . ,(getf result :best-move))))))

(hunchentoot:define-easy-handler (scan-game-handler :uri "/scan-game") ()
  (handle-cors)
  (setf (hunchentoot:content-type*) "application/json")
  (if *current-game-moves*
      (let ((analysis (scan-game *current-game-moves*)))
        (cl-json:encode-json-to-string `((:success . t) (:analysis . ,analysis))))
      (cl-json:encode-json-to-string '((:error . "No game loaded")))))

(defun start-server (&key (port 8080))
  (when *acceptor*
    (hunchentoot:stop *acceptor*))
  
  ;; Reset dispatch table to avoid duplicates during restarts
  (setf hunchentoot:*dispatch-table* (list 'hunchentoot:dispatch-easy-handlers))
  
  ;; (init-new-game-log)
  
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
