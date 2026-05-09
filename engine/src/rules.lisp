(in-package :chess-engine)

;; Utility to convert 0-63 to x, y
(defun sq-x (sq) (mod sq 8))
(defun sq-y (sq) (floor sq 8))
(defun make-sq (x y) (+ (* y 8) x))
(defun in-bounds (x y) (and (>= x 0) (< x 8) (>= y 0) (< y 8)))

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
         (dir (if (eq color :white) -1 1))) ; white moves up (-y), black down (+y)
    
    (flet ((add-move (nx ny)
             (when (in-bounds nx ny)
               (let ((target (make-sq nx ny)))
                 (let ((p (get-piece state target)))
                   (if p
                       (when (enemy-p piece p)
                         (push target moves)
                         t) ; hit piece, stop ray
                       (progn
                         (push target moves)
                         nil)))))) ; continue ray
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
                      (when (and p (enemy-p piece p))
                        (push target moves))))))
        
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
                          (push target moves))))))))
      
      moves)))

(defun legal-moves (state sq)
  "For now, returns pseudo-legal moves. Full check validation can be added."
  (pseudo-legal-moves state sq))

(defun make-move (state from to)
  "Execute a move on the game state if it is legal."
  (let ((piece (get-piece state from))
        (moves (legal-moves state from)))
    (if (member to moves)
        (progn
          (setf (aref (game-state-board state) to) piece)
          (setf (aref (game-state-board state) from) nil)
          ;; Toggle active color
          (setf (game-state-active-color state)
                (if (eq (game-state-active-color state) :white) :black :white))
          t)
        nil)))
