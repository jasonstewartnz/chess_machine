(in-package :chess-engine)

(defun get-piece-symbol-for-san (type)
  (case type
    (:knight "N")
    (:bishop "B")
    (:rook "R")
    (:queen "Q")
    (:king "K")
    (t ""))) ; Pawns have no symbol

(defun get-disambiguation (state from to type color)
  "Returns the disambiguation string for a move."
  (if (eq type :pawn)
      ""
      (let ((ambiguous-sqs nil))
        ;; Find all other pieces of the same type and color that can move to TO
        (loop for i from 0 to 63
              for p = (get-piece state i)
              do (when (and p 
                            (not (= i from))
                            (eq (piece-type p) type)
                            (eq (piece-color p) color))
                   (when (member to (legal-moves state i))
                     (push i ambiguous-sqs))))
        (if (null ambiguous-sqs)
            ""
            ;; We have ambiguity
            (let* ((from-file (subseq (sq-to-algebraic from) 0 1))
                   (from-rank (subseq (sq-to-algebraic from) 1 2))
                   (file-unique t)
                   (rank-unique t))
              (loop for sq in ambiguous-sqs
                    do (let ((f (subseq (sq-to-algebraic sq) 0 1))
                             (r (subseq (sq-to-algebraic sq) 1 2)))
                         (when (string= f from-file) (setf file-unique nil))
                         (when (string= r from-rank) (setf rank-unique nil))))
              (cond
                (file-unique from-file)
                (rank-unique from-rank)
                (t (sq-to-algebraic from))))))))

(defun move-to-san (state from to)
  "Convert a move to Standard Algebraic Notation (SAN)."
  (let* ((piece (get-piece state from))
         (type (piece-type piece))
         (color (piece-color piece))
         (is-capture (not (null (get-piece state to))))
         (is-en-passant (and (eq type :pawn)
                             (not (= (sq-x from) (sq-x to)))
                             (null (get-piece state to))))
         (is-castling-kingside (and (eq type :king) (= (- to from) 2)))
         (is-castling-queenside (and (eq type :king) (= (- from to) 2)))
         (is-promotion (and (eq type :pawn) (or (= (sq-y to) 0) (= (sq-y to) 7))))
         (target-sq-str (sq-to-algebraic to)))
    
    (cond
      (is-castling-kingside "O-O")
      (is-castling-queenside "O-O-O")
      (t
       (let* ((piece-str (get-piece-symbol-for-san type))
              (disambig (get-disambiguation state from to type color))
              (capture-str (if (or is-capture is-en-passant) "x" ""))
              ;; Pawns need the starting file if they capture
              (pawn-file (if (and (eq type :pawn) (string= capture-str "x"))
                             (subseq (sq-to-algebraic from) 0 1)
                             ""))
              (promo-str (if is-promotion "=Q" ""))
              ;; Build base move string
              (base-san (concatenate 'string 
                                     piece-str 
                                     pawn-file 
                                     disambig 
                                     capture-str 
                                     target-sq-str 
                                     promo-str)))
         
         ;; For castling and en passant, make-test-move doesn't move the rook or remove the captured pawn,
         ;; but it's usually enough for check detection. However, to be 100% accurate, we should actually copy and make-move!
         (let ((full-test-state (copy-state state)))
           (make-move full-test-state from to)
           (let ((status (get-game-status full-test-state)))
             (cond
               ((eq status :checkmate) (concatenate 'string base-san "#"))
               ((eq status :check) (concatenate 'string base-san "+"))
               (t base-san)))))))))

(defvar *current-game-file* nil)

(defun get-timestamp-string ()
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time (get-universal-time))
    (format nil "~4,'0d-~2,'0d-~2,'0d_~2,'0d~2,'0d~2,'0d" year month date hour minute second)))

(defun get-date-string ()
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time (get-universal-time))
    (declare (ignore second minute hour))
    (format nil "~4,'0d.~2,'0d.~2,'0d" year month date)))

(defun init-new-game-log ()
  "Initialize a new PGN log file for the game."
  (ensure-directories-exist "games/")
  (let ((filename (format nil "games/game_~A.pgn" (get-timestamp-string))))
    (setf *current-game-file* filename)
    (with-open-file (stream filename :direction :output :if-does-not-exist :create)
      (format stream "[Event \"Casual Game\"]~%")
      (format stream "[Site \"Localhost\"]~%")
      (format stream "[Date \"~A\"]~%" (get-date-string))
      (format stream "[Round \"1\"]~%")
      (format stream "[White \"Player 1\"]~%")
      (format stream "[Black \"Player 2\"]~%")
      (format stream "[Result \"*\"]~%~%"))))

(defun append-move-to-log (san active fullmove)
  "Append a SAN move to the current game log."
  (when *current-game-file*
    (with-open-file (stream *current-game-file* :direction :output :if-exists :append :if-does-not-exist :create)
      ;; active is the color BEFORE the move.
      ;; So if active is :white, we prepend "1. "
      (if (eq active :white)
          (format stream "~A. ~A " fullmove san)
          (format stream "~A " san)))))
