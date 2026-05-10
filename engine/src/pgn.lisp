(in-package :chess-engine)

;;; PGN Parsing Logic
;;; This module converts Standard Algebraic Notation (SAN) moves into square indices.

(defun parse-san-move (state san)
  "Convert a SAN string (e.g., 'Nf3', 'e4', 'O-O') into a list (from to)."
  (let ((clean-san (remove-if (lambda (c) (member c '(#\+ #\# #\! #\?))) san)))
    (cond
      ((string= clean-san "O-O") 
       (let ((rank (if (eq (game-state-active-color state) :white) 7 0)))
         (list (make-sq 4 rank) (make-sq 6 rank))))
      ((string= clean-san "O-O-O")
       (let ((rank (if (eq (game-state-active-color state) :white) 7 0)))
         (list (make-sq 4 rank) (make-sq 2 rank))))
      (t 
       (parse-regular-san state clean-san)))))

(defun parse-regular-san (state san)
  "Handles non-castling SAN moves like e4, Nf3, exd5."
  (let* ((color (game-state-active-color state))
         (type (identify-piece-type san))
         (to-sq (identify-target-square san))
         (disambiguation (identify-disambiguation san type)))
    ;; Find all pieces of TYPE and COLOR that can legally move to TO-SQ
    (let ((candidates (find-candidates state type color to-sq disambiguation)))
      (if (= (length candidates) 1)
          (list (first candidates) to-sq)
          (error "Ambiguous or illegal SAN move: ~A" san)))))

(defun identify-piece-type (san)
  (case (char san 0)
    (#\N :knight)
    (#\B :bishop)
    (#\R :rook)
    (#\Q :queen)
    (#\K :king)
    (t :pawn)))

(defun identify-target-square (san)
  "Target square is the first occurrence of file+rank (e.g., e4) that isn't the disambiguation."
  ;; Target square in SAN is almost always the last 2 characters before any promotion/check marks
  (let* ((clean (remove-if (lambda (c) (member c '(#\+ #\# #\! #\? #\= #\Q #\R #\B #\N))) 
                           (subseq san (if (upper-case-p (char san 0)) 1 0))))
         (len (length clean)))
    (parse-algebraic (subseq clean (- len 2)))))

(defun parse-algebraic (coord)
  "Convert 'e4' to index."
  (let ((file (- (char-code (char coord 0)) (char-code #\a)))
        (rank (- 8 (digit-char-p (char coord 1)))))
    (make-sq file rank)))

(defun identify-disambiguation (san type)
  "Extract file or rank disambiguation (e.g., 'Nbd2' -> #\b)."
  (if (eq type :pawn)
      (if (find #\x san) (char san 0) nil)
      (let ((part (subseq san 1 (- (length san) 2))))
        (let ((dis (remove #\x part)))
          (if (string= dis "") nil dis)))))

(defun find-candidates (state type color to-sq disambiguation)
  (let ((results nil))
    (loop for i from 0 to 63
          for p = (aref (game-state-board state) i)
          do (when (and p (eq (piece-color p) color) (eq (piece-type p) type))
               (let ((legal (legal-moves state i)))
                 (when (and (member to-sq legal)
                            (matches-disambiguation i disambiguation))
                   (push i results)))))
    results))

(defun matches-disambiguation (sq dis)
  (if (or (null dis) (and (stringp dis) (= (length dis) 0)))
      t
      (let ((char (if (stringp dis) (char dis 0) dis)))
        (if (digit-char-p char)
            (= (sq-y sq) (- 8 (digit-char-p char)))
            (= (sq-x sq) (- (char-code char) (char-code #\a)))))))

(defun parse-pgn-game (pgn-string)
  "Parses a full PGN string and returns a list of (from to) moves."
  (let* ((headers (extract-pgn-headers pgn-string))
         (fen (cdr (assoc :FEN headers)))
         (clean-pgn (strip-pgn-annotations pgn-string))
         (tokens (split-sequence:split-sequence #\Space clean-pgn))
         (move-texts (remove-if (lambda (tok) 
                                  (or (string= tok "") 
                                      (digit-char-p (char tok 0))
                                      (string= tok "1-0") (string= tok "0-1") (string= tok "1/2-1/2") (string= tok "*")))
                                tokens))
         (temp-state (if fen (parse-fen fen) (initial-board)))
         (all-moves nil))
    (dolist (san move-texts)
      (let ((m (parse-san-move temp-state san)))
        (push m all-moves)
        (apply-move temp-state (first m) (second m))))
    (reverse all-moves)))

(defun strip-pgn-annotations (pgn)
  "Removes headers [..] and comments {..} from PGN string."
  (let ((out "")
        (in-header nil)
        (in-comment nil))
    (loop for c across pgn
          do (cond
               ((char= c #\[) (setf in-header t))
               ((char= c #\]) (setf in-header nil))
               ((char= c #\{) (setf in-comment t))
               ((char= c #\}) (setf in-comment nil))
               ((and (not in-header) (not in-comment))
                (setf out (concatenate 'string out (string c))))))
    (substitute #\Space #\Newline out)))

(defun parse-pgn-collection (pgn-string)
  "Splits a multi-game PGN string into individual games."
  (let ((games nil)
        (current-game ""))
    (dolist (line (split-sequence:split-sequence #\Newline pgn-string))
      (if (and (not (string= current-game ""))
               (alexandria:starts-with-subseq "[Event " line))
          (progn
            (push (parse-single-game current-game) games)
            (setf current-game line))
          (setf current-game (concatenate 'string current-game (string #\Newline) line))))
    (when (not (string= current-game ""))
      (push (parse-single-game current-game) games))
    (reverse games)))

(defun parse-single-game (pgn-text)
  "Extracts headers and moves from a single PGN game block."
  (let ((headers (extract-pgn-headers pgn-text))
        (moves (parse-pgn-game pgn-text)))
    `((:headers . ,headers)
      (:moves . ,moves))))

(defun extract-pgn-headers (pgn-text)
  "Simple regex-free header extraction."
  (let ((headers nil))
    (dolist (line (split-sequence:split-sequence #\Newline pgn-text))
      (when (and (> (length line) 0) (char= (char line 0) #\[))
        (let* ((space-idx (position #\Space line))
               (key (subseq line 1 space-idx))
               (val (subseq line (+ space-idx 2) (- (length line) 2))))
          (push (cons (intern (string-upcase key) :keyword) val) headers))))
    headers))

(defun apply-move (state from to)
  "Update state with castling and promotion support during parsing."
  (let ((piece (aref (game-state-board state) from)))
    (when piece
      ;; 1. Handle Castling (move the rook)
      (when (and (eq (piece-type piece) :king) (= (abs (- (sq-x from) (sq-x to))) 2))
        (cond
          ((= to 62) (setf (aref (game-state-board state) 61) (aref (game-state-board state) 63)
                           (aref (game-state-board state) 63) nil))
          ((= to 58) (setf (aref (game-state-board state) 59) (aref (game-state-board state) 56)
                           (aref (game-state-board state) 56) nil))
          ((= to 6)  (setf (aref (game-state-board state) 5) (aref (game-state-board state) 7)
                           (aref (game-state-board state) 7) nil))
          ((= to 2)  (setf (aref (game-state-board state) 3) (aref (game-state-board state) 0)
                           (aref (game-state-board state) 0) nil))))
      ;; 2. Standard Move
      (setf (aref (game-state-board state) from) nil)
      (setf (aref (game-state-board state) to) piece)
      ;; 3. Handle Promotion
      (when (and (eq (piece-type piece) :pawn) (or (= (sq-y to) 0) (= (sq-y to) 7)))
        (setf (aref (game-state-board state) to) (make-piece :color (piece-color piece) :type :queen)))
      ;; 4. Toggle color
      (setf (game-state-active-color state) 
            (if (eq (game-state-active-color state) :white) :black :white)))))
