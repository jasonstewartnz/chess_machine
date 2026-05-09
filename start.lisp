;; Script to start the chess engine backend

;; Ensure Quicklisp is loaded even when running as a script (which skips ~/.sbclrc)
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                       (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload "hunchentoot")
(ql:quickload "cl-json")
(ql:quickload "alexandria")

;; Load the ASD definition and compile the project
(asdf:load-asd (merge-pathnames "engine/chess-engine.asd" *default-pathname-defaults*))
(asdf:load-system "chess-engine" :force t)

;; Start the server on port 8080
(chess-engine:start-server :port 8080)

(format t "--------------------------------------------------------~%")
(format t "Chess Engine Server is running at http://localhost:8080~%")
(format t "Open frontend/index.html in your browser to play!~%")
(format t "Press Enter to stop the server and exit...~%")
(read-line)
(chess-engine:stop-server)
(quit)
