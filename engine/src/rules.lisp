(in-package :chess-engine)

;; Utility to convert 0-63 to x, y
(defun sq-x (sq) (mod sq 8))
(defun sq-y (sq) (floor sq 8))
(defun make-sq (x y) (+ (* y 8) x))
(defun in-bounds (x y) (and (>= x 0) (< x 8) (>= y 0) (< y 8)))
(defun sq-to-algebraic (sq)
  (format nil "~A~A" (code-char (+ 97 (sq-x sq))) (- 8 (sq-y sq))))

(defun get-piece (state sq)
  (aref (game-state-board state) sq))

(defun enemy-p (p1 p2)
  (and p1 p2 (not (eq (piece-color p1) (piece-color p2)))))

(defun empty-p (state sq)
  (null (get-piece state sq)))

(defun pseudo-legal-moves (state sq)
  "Generate pseudo-legal moves (ignoring check) for a piece at SQ."
  (let* ((piece (get-piece state sq))
         (color (piece-color piece))
         (type (piece-type piece))
         (x (sq-x sq))
         (y (sq-y sq))
         (moves nil)
         (dir (if (eq color :white) -1 1)))
    
    (labels ((add-move (nx ny)
             (when (in-bounds nx ny)
               (let* ((target (make-sq nx ny))
                      (p (get-piece state target)))
                 (if p
                     (progn
                       (when (enemy-p piece p)
                         (push target moves))
                       t) ; Stop ray if any piece is hit
                     (progn
                       (push target moves)
                       nil))))) ; Continue ray if square is empty
           (ray (dx dy)
             (loop for nx = (+ x dx) then (+ nx dx)
                   for ny = (+ y dy) then (+ ny dy)
                   while (in-bounds nx ny)
                   do (if (add-move nx ny) (return)))))
      
      (case type
        (:pawn
         ;; Move 1
         (let ((nx x) (ny (+ y dir)))
           (when (and (in-bounds nx ny) (empty-p state (make-sq nx ny)))
             (push (make-sq nx ny) moves)
             ;; Move 2
             (let ((start-y (if (eq color :white) 6 1)))
               (when (and (= y start-y) (empty-p state (make-sq nx (+ ny dir))))
                 (push (make-sq nx (+ ny dir)) moves)))))
         ;; Captures
         (loop for dx in '(-1 1)
               for nx = (+ x dx)
               for ny = (+ y dir)
               do (when (in-bounds nx ny)
                    (let* ((target (make-sq nx ny))
                           (p (get-piece state target)))
                      (if (and p (enemy-p piece p))
                          (push target moves)
                          (let ((ep (game-state-en-passant state)))
                            (when (and ep (string= (sq-to-algebraic target) ep))
                              (push target moves))))))))
        
        (:knight
         (loop for (dx dy) in '((-2 -1) (-2 1) (-1 -2) (-1 2)
                                (1 -2) (1 2) (2 -1) (2 1))
               do (let ((nx (+ x dx)) (ny (+ y dy)))
                    (when (in-bounds nx ny)
                      (let* ((target (make-sq nx ny))
                             (p (get-piece state target)))
                        (when (or (null p) (enemy-p piece p))
                          (push target moves)))))))
        
        (:bishop
         (loop for (dx dy) in '((-1 -1) (-1 1) (1 -1) (1 1))
               do (ray dx dy)))
        
        (:rook
         (loop for (dx dy) in '((-1 0) (1 0) (0 -1) (0 1))
               do (ray dx dy)))
        
        (:queen
         (loop for (dx dy) in '((-1 -1) (-1 1) (1 -1) (1 1)
                                (-1 0) (1 0) (0 -1) (0 1))
               do (ray dx dy)))
        
        (:king
         (loop for (dx dy) in '((-1 -1) (-1 1) (1 -1) (1 1)
                                (-1 0) (1 0) (0 -1) (0 1))
               do (let ((nx (+ x dx)) (ny (+ y dy)))
                    (when (in-bounds nx ny)
                      (let* ((target (make-sq nx ny))
                             (p (get-piece state target)))
                        (when (or (null p) (enemy-p piece p))
                          (push target moves))))))
         ;; Castling
         (let ((castling (game-state-castling state))
               (enemy (if (eq color :white) :black :white)))
           (if (eq color :white)
               (progn
                 (when (and (member :K castling)
                            (empty-p state 61) (empty-p state 62)
                            (not (attacked-p state 60 enemy))
                            (not (attacked-p state 61 enemy))
                            (not (attacked-p state 62 enemy)))
                   (push 62 moves))
                 (when (and (member :Q castling)
                            (empty-p state 59) (empty-p state 58) (empty-p state 57)
                            (not (attacked-p state 60 enemy))
                            (not (attacked-p state 59 enemy))
                            (not (attacked-p state 58 enemy)))
                   (push 58 moves)))
               (progn
                 (when (and (member :|k| castling)
                            (empty-p state 5) (empty-p state 6)
                            (not (attacked-p state 4 enemy))
                            (not (attacked-p state 5 enemy))
                            (not (attacked-p state 6 enemy)))
                   (push 6 moves))
                 (when (and (member :|q| castling)
                            (empty-p state 3) (empty-p state 2) (empty-p state 1)
                            (not (attacked-p state 4 enemy))
                            (not (attacked-p state 3 enemy))
                            (not (attacked-p state 2 enemy)))
                   (push 2 moves)))))))
      
      moves)))

(defun attacked-p (state sq attacker-color)
  "Check if SQ is attacked by ATTACKER-COLOR."
  (let ((x (sq-x sq))
        (y (sq-y sq))
        (pawn-dir (if (eq attacker-color :white) 1 -1)))
    (flet ((check-ray (dx dy piece-types)
             (loop for nx = (+ x dx) then (+ nx dx)
                   for ny = (+ y dy) then (+ ny dy)
                   while (in-bounds nx ny)
                   do (let ((p (get-piece state (make-sq nx ny))))
                        (when p
                          (if (and (eq (piece-color p) attacker-color)
                                   (member (piece-type p) piece-types))
                              (return-from check-ray t)
                              (return-from check-ray nil))))))
           (check-jump (dx dy piece-type)
             (let ((nx (+ x dx)) (ny (+ y dy)))
               (when (in-bounds nx ny)
                 (let ((p (get-piece state (make-sq nx ny))))
                   (and p (eq (piece-color p) attacker-color) (eq (piece-type p) piece-type)))))))
      
      (loop for (dx dy) in '((-2 -1) (-2 1) (-1 -2) (-1 2) (1 -2) (1 2) (2 -1) (2 1))
            do (when (check-jump dx dy :knight) (return-from attacked-p t)))
      (loop for (dx dy) in '((-1 -1) (-1 1) (1 -1) (1 1) (-1 0) (1 0) (0 -1) (0 1))
            do (when (check-jump dx dy :king) (return-from attacked-p t)))
      (loop for dx in '(-1 1)
            do (when (check-jump dx pawn-dir :pawn) (return-from attacked-p t)))
      (loop for (dx dy) in '((-1 0) (1 0) (0 -1) (0 1))
            do (when (check-ray dx dy '(:rook :queen)) (return-from attacked-p t)))
      (loop for (dx dy) in '((-1 -1) (-1 1) (1 -1) (1 1))
            do (when (check-ray dx dy '(:bishop :queen)) (return-from attacked-p t)))
      nil)))

(defun in-check-p (state color)
  "Return true if the king of COLOR is in check."
  (let ((king-sq nil)
        (enemy-color (if (eq color :white) :black :white)))
    (loop for i from 0 to 63
          for p = (get-piece state i)
          do (when (and p (eq (piece-color p) color) (eq (piece-type p) :king))
               (setf king-sq i)
               (return)))
    (if king-sq
        (attacked-p state king-sq enemy-color)
        nil)))

(defun make-test-move (state from to)
  "Creates a copy of the state and executes the move for validation."
  (let ((new-state (copy-state state))
        (piece (get-piece state from)))
    (setf (aref (game-state-board new-state) to) piece)
    (setf (aref (game-state-board new-state) from) nil)
    new-state))

(defun legal-moves (state sq)
  "Returns all legal moves for the piece at SQ, filtering out moves that result in self-check. Enforces turn order in :game mode."
  (let* ((piece (get-piece state sq))
         (color (piece-color piece)))
    (if (and (eq *game-mode* :game)
             (not (eq color (game-state-active-color state))))
        nil
        (let* ((pseudo (pseudo-legal-moves state sq))
               (legal nil))
          (loop for to in pseudo
                do (let ((test-state (make-test-move state sq to)))
                     (unless (in-check-p test-state color)
                       (push to legal))))
          legal))))

(defun make-move (state from to)
  "Execute a move on the game state if it is legal."
  (let ((piece (get-piece state from))
        (moves (legal-moves state from)))
    (if (member to moves)
        (progn
          ;; 1. Check for Castling to move the rook
          (let ((is-castling (and (eq (piece-type piece) :king) (= (abs (- from to)) 2))))
            (when is-castling
              (cond
                ((= to 62) (setf (aref (game-state-board state) 61) (get-piece state 63)
                                 (aref (game-state-board state) 63) nil))
                ((= to 58) (setf (aref (game-state-board state) 59) (get-piece state 56)
                                 (aref (game-state-board state) 56) nil))
                ((= to 6)  (setf (aref (game-state-board state) 5) (get-piece state 7)
                                 (aref (game-state-board state) 7) nil))
                ((= to 2)  (setf (aref (game-state-board state) 3) (get-piece state 0)
                                 (aref (game-state-board state) 0) nil)))))
          
          ;; 2. Check for En Passant capture
          (let ((is-en-passant (and (eq (piece-type piece) :pawn)
                                    (not (= (sq-x from) (sq-x to)))
                                    (null (get-piece state to)))))
            (when is-en-passant
              (let ((cap-sq (make-sq (sq-x to) (sq-y from))))
                (setf (aref (game-state-board state) cap-sq) nil))))
          
          ;; 3. Update En Passant state
          (setf (game-state-en-passant state)
                (if (and (eq (piece-type piece) :pawn)
                         (= (abs (- (sq-y from) (sq-y to))) 2))
                    (sq-to-algebraic (make-sq (sq-x from) (/ (+ (sq-y from) (sq-y to)) 2)))
                    nil))
          
          ;; 4. Check for Pawn Promotion (Auto Queen)
          (when (and (eq (piece-type piece) :pawn)
                     (or (= (sq-y to) 0) (= (sq-y to) 7)))
            (setf piece (make-piece :color (piece-color piece) :type :queen)))
            
          ;; 5. Update Castling Rights
          (when (eq (piece-type piece) :king)
            (setf (game-state-castling state)
                  (if (eq (piece-color piece) :white)
                      (remove :K (remove :Q (game-state-castling state)))
                      (remove :|k| (remove :|q| (game-state-castling state))))))
          (let ((castling (game-state-castling state)))
            (when (or (= from 63) (= to 63)) (setf castling (remove :K castling)))
            (when (or (= from 56) (= to 56)) (setf castling (remove :Q castling)))
            (when (or (= from 7) (= to 7)) (setf castling (remove :|k| castling)))
            (when (or (= from 0) (= to 0)) (setf castling (remove :|q| castling)))
            (setf (game-state-castling state) castling))
            
          ;; 6. Finalize move
          (setf (aref (game-state-board state) to) piece)
          (setf (aref (game-state-board state) from) nil)
          (setf (game-state-active-color state)
                (if (eq (game-state-active-color state) :white) :black :white))
          t)
        nil)))

(defun get-game-status (state)
  "Returns :active, :checkmate, or :stalemate."
  (let* ((color (game-state-active-color state))
         (has-moves nil))
    (loop for i from 0 to 63
          for p = (get-piece state i)
          do (when (and p (eq (piece-color p) color))
               (when (legal-moves state i)
                 (setf has-moves t)
                 (return))))
    (if has-moves
        (if (in-check-p state color) :check :active)
        (if (in-check-p state color) :checkmate :stalemate))))
