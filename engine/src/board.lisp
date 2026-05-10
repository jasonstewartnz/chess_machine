(in-package :chess-engine)

(defstruct piece
  color ; :white or :black
  type) ; :pawn, :knight, :bishop, :rook, :queen, :king

(defstruct game-state
  (board (make-array 64 :initial-element nil))
  (active-color :white)
  (castling '(:K :Q :|k| :|q|))
  (en-passant nil)
  (halfmove 0)
  (fullmove 1))

(defvar *game-mode* :game)

(defun copy-state (state)
  "Create a copy of the game state, including a new board array."
  (let ((new-state (copy-game-state state)))
    (setf (game-state-board new-state) (copy-seq (game-state-board state)))
    (setf (game-state-castling new-state) (copy-list (game-state-castling state)))
    new-state))

(defun char-to-piece (c)
  "Convert a FEN character to a piece struct."
  (let ((color (if (upper-case-p c) :white :black))
        (type (case (char-downcase c)
                (#\p :pawn)
                (#\n :knight)
                (#\b :bishop)
                (#\r :rook)
                (#\q :queen)
                (#\k :king))))
    (if type (make-piece :color color :type type) nil)))

(defun parse-fen (fen)
  "Parse a FEN string into a GAME-STATE."
  (let* ((parts (uiop:split-string fen :separator '(#\Space)))
         (placement (nth 0 parts))
         (active (nth 1 parts))
         (castling (nth 2 parts))
         (ep (nth 3 parts))
         (half (or (nth 4 parts) "0"))
         (full (or (nth 5 parts) "1"))
         (state (make-game-state)))
    
    ;; Parse piece placement
    (let ((square 0))
      (loop for c across placement
            do (cond
                 ((char= c #\/) nil) ; skip slashes
                 ((digit-char-p c)
                  (incf square (parse-integer (string c))))
                 (t
                  (setf (aref (game-state-board state) square)
                        (char-to-piece c))
                  (incf square)))))
    
    ;; Parse active color
    (setf (game-state-active-color state)
          (if (and active (string= active "b")) :black :white))
    
    ;; Parse castling
    (let ((c-list nil))
      (when (and castling (not (string= castling "-")))
        (loop for c across castling
              do (push (intern (string c) :keyword) c-list)))
      (setf (game-state-castling state) c-list))
    
    ;; Parse en-passant (simplified: just store the string if not "-")
    (setf (game-state-en-passant state)
          (if (and ep (not (string= ep "-"))) ep nil))
    
    ;; Parse move clocks
    (setf (game-state-halfmove state) (parse-integer half :junk-allowed t))
    (setf (game-state-fullmove state) (parse-integer full :junk-allowed t))
    
    state))

(defparameter *initial-fen* "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

(defun initial-board ()
  "Returns the initial game state."
  (parse-fen *initial-fen*))

(defun get-piece-counts (state)
  (let ((counts (make-hash-table :test 'equal)))
    (loop for i from 0 to 63
          for p = (get-piece state i)
          do (when p
               (let ((key (format nil "~A-~A" 
                                  (string-downcase (symbol-name (piece-color p)))
                                  (string-downcase (symbol-name (piece-type p))))))
                 (incf (gethash key counts 0)))))
    (let ((alist nil))
      (maphash (lambda (k v) 
                 (push (cons k v) alist)) 
               counts)
      alist)))

(defun piece-to-alist (piece)
  (if piece
      `((:color . ,(string-downcase (symbol-name (piece-color piece))))
        (:type . ,(string-downcase (symbol-name (piece-type piece)))))
      nil))

(defun generate-fen (state)
  "Generate a FEN string from a GAME-STATE."
  (let ((board (game-state-board state)))
    (with-output-to-string (s)
      ;; 1. Piece placement
      (loop for y from 0 to 7
            do (let ((empty 0))
                 (loop for x from 0 to 7
                       for sq = (make-sq x y)
                       for p = (aref board sq)
                       do (if p
                              (progn
                                (when (> empty 0) (princ empty s) (setf empty 0))
                                (let ((char (case (piece-type p)
                                              (:pawn #\p)
                                              (:knight #\n)
                                              (:bishop #\b)
                                              (:rook #\r)
                                              (:queen #\q)
                                              (:king #\k))))
                                  (princ (if (eq (piece-color p) :white)
                                             (char-upcase char)
                                             char)
                                         s)))
                              (incf empty)))
                 (when (> empty 0) (princ empty s))
                 (when (< y 7) (princ #\/ s))))
      
      ;; 2. Active color
      (format s " ~A" (if (eq (game-state-active-color state) :white) "w" "b"))
      
      ;; 3. Castling
      (let ((c (game-state-castling state)))
        (format s " ")
        (if (null c)
            (princ "-" s)
            (progn
              (when (member :K c) (princ "K" s))
              (when (member :Q c) (princ "Q" s))
              (when (member :|k| c) (princ "k" s))
              (when (member :|q| c) (princ "q" s)))))
      
      ;; 4. En passant
      (format s " ~A" (or (game-state-en-passant state) "-"))
      
      ;; 5. Halfmove and Fullmove
      (format s " ~A ~A" (game-state-halfmove state) (game-state-fullmove state)))))

(defun game-state-to-alist (state)
  (let ((board-list (loop for i from 0 to 63
                          collect (piece-to-alist (aref (game-state-board state) i)))))
    `((:board . ,board-list)
      (:active-color . ,(string-downcase (symbol-name (game-state-active-color state))))
      (:castling . ,(mapcar (lambda (k) (symbol-name k)) (game-state-castling state)))
      (:en-passant . ,(game-state-en-passant state))
      (:halfmove . ,(game-state-halfmove state))
      (:fullmove . ,(game-state-fullmove state))
      (:material . ,(get-piece-counts state))
      (:mode . ,(string-downcase (symbol-name *game-mode*)))
      (:fen . ,(generate-fen state)))))
