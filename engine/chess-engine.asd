(in-package :asdf-user)

(defsystem "chess-engine"
  :description "A chess engine and REST API built in Common Lisp"
  :version "0.1.0"
  :author "Antigravity"
  :depends-on ("hunchentoot" "cl-json" "alexandria")
  :components ((:module "src"
                :components
                ((:file "packages")
                 (:file "board" :depends-on ("packages"))
                 (:file "rules" :depends-on ("board"))
                 (:file "server" :depends-on ("rules"))))))
