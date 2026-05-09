(defpackage :chess-engine
  (:use :cl :alexandria)
  (:export #:start-server
           #:stop-server
           #:parse-fen
           #:initial-board
           #:board-to-json
           #:make-move
           #:legal-moves))
