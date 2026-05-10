(in-package :chess-engine)

;;; Stockfish UCI Bridge
;;; Manages a background Stockfish process and communicates via UCI protocol.

(defvar *stockfish-process* nil)
(defvar *stockfish-path* (merge-pathnames "bin/stockfish/stockfish-macos-m1-apple-silicon" (uiop:pathname-parent-directory-pathname (asdf:system-source-directory :chess-engine))))

(defun start-stockfish ()
  "Launches the Stockfish process."
  (unless (and *stockfish-process* (uiop:process-alive-p *stockfish-process*))
    (setf *stockfish-process* 
          (uiop:launch-program (namestring *stockfish-path*)
                               :input :stream
                               :output :stream
                               :error-output :output))
    (write-uci-line "uci")
    (wait-for-uci-response "uciok")))

(defun stop-stockfish ()
  (when (and *stockfish-process* (uiop:process-alive-p *stockfish-process*))
    (write-uci-line "quit")
    (uiop:wait-process *stockfish-process*)
    (setf *stockfish-process* nil)))

(defun write-uci-line (line)
  (let ((stream (uiop:process-info-input *stockfish-process*)))
    (format stream "~A~%" line)
    (finish-output stream)))

(defun read-uci-line ()
  (read-line (uiop:process-info-output *stockfish-process*) nil))

(defun wait-for-uci-response (target)
  (loop for line = (read-uci-line)
        while line
        until (alexandria:starts-with-subseq target line)
        collect line))

(defun analyze-position (fen &key (depth 15))
  "Sends a position to Stockfish and returns evaluation and best move."
  (start-stockfish)
  (write-uci-line (format nil "position fen ~A" fen))
  (write-uci-line (format nil "go depth ~A" depth))
  (let ((eval-info nil)
        (best-move nil))
    (loop for line = (read-uci-line)
          while line
          do (cond
               ((alexandria:starts-with-subseq "info" line)
                (let ((score-idx (search "score cp" line)))
                  (when score-idx
                    (let* ((rest (subseq line (+ score-idx 9)))
                           (space-idx (position #\Space rest))
                           (score (parse-integer (subseq rest 0 space-idx))))
                      (setf eval-info score)))))
               ((alexandria:starts-with-subseq "bestmove" line)
                (setf best-move (subseq line 9 13))
                (return))))
    (list :score eval-info :best-move best-move)))

(defun scan-game (moves)
  "Analyzes a list of moves and returns eval history."
  (let ((temp-state (initial-board))
        (history nil))
    (push (analyze-position (generate-fen temp-state)) history)
    (dolist (m moves)
      (apply-move temp-state (first m) (second m))
      (push (analyze-position (generate-fen temp-state)) history))
    (reverse history)))
