; Prove you can't win at tic-tac-toe if the oppontent is competent
; Tested with PC-LISP V3.00. Likely won't work with more modern LISP implementations.
; This takes roughly half an hour to run on a 4.77Mhz 8088.
; This runs in about 4 seconds in the NTVDM emulator on an AMD 5950x
; I am not proficient in LISP; there are likely easy ways to improve performance.
; More recent versions of LISP have functions including:
;    /= not equal
;    bitwise operators like logand
;    byte datatype instead of 4-byte integers
; But Common LISP doesn't seem to have hunks.

(setq score-win 6)
(setq score-tie 5)
(setq score-lose 4)
(setq score-max 9)
(setq score-min 2)
(setq piece-blank 0)
(setq piece-x 1)
(setq piece-y 2)
(setq moves 0)
(setq board (hunk 0 0 0 0 0 0 0 0 0))

(defun b( index )  ; shorthand for reading a board position at the cost of perf
    (cxr index board)
)

(defun winner() (prog ();
    (cond ((and (not (= (b 0) piece-blank)) (= (b 0) (b 1)) (= (b 0) (b 2))) (return (b 0)))
          ((and (not (= (b 0) piece-blank)) (= (b 0) (b 3)) (= (b 0) (b 6))) (return (b 0)))
          ((and (not (= (b 1) piece-blank)) (= (b 1) (b 4)) (= (b 1) (b 7))) (return (b 1)))
          ((and (not (= (b 2) piece-blank)) (= (b 2) (b 5)) (= (b 2) (b 8))) (return (b 2)))
          ((and (not (= (b 3) piece-blank)) (= (b 3) (b 4)) (= (b 3) (b 5))) (return (b 3)))
          ((and (not (= (b 4) piece-blank)) (= (b 4) (b 0)) (= (b 4) (b 8))) (return (b 4)))
          ((and (not (= (b 4) piece-blank)) (= (b 4) (b 2)) (= (b 4) (b 6))) (return (b 4)))
          ((and (not (= (b 6) piece-blank)) (= (b 6) (b 7)) (= (b 6) (b 8))) (return (b 6)))
    )

    (return piece-blank)
))

(defun proc0() (prog (x)
    (setq x (b 0)) 
    (cond ((or (and (= x (b 1)) (= x (b 2)))
               (and (= x (b 3)) (= x (b 6)))
               (and (= x (b 4)) (= x (b 8))))
           (return x)))
    (return piece-blank)
))

(defun proc1() (prog (x)
    (setq x (b 1)) 
    (cond ((or (and (= x (b 0)) (= x (b 2)))
               (and (= x (b 4)) (= x (b 7))))
           (return x)))
    (return piece-blank)
))

(defun proc2() (prog (x)
    (setq x (b 2)) 
    (cond ((or (and (= x (b 0)) (= x (b 1)))
               (and (= x (b 5)) (= x (b 8)))
               (and (= x (b 4)) (= x (b 6))))
           (return x)))
    (return piece-blank)
))

(defun proc3() (prog (x)
    (setq x (b 3)) 
    (cond ((or (and (= x (b 4)) (= x (b 5)))
               (and (= x (b 0)) (= x (b 6))))
           (return x)))
    (return piece-blank)
))

(defun proc4() (prog (x)
    (setq x (b 4)) 
    (cond ((or (and (= x (b 0)) (= x (b 8)))
               (and (= x (b 2)) (= x (b 6)))
               (and (= x (b 1)) (= x (b 7)))
               (and (= x (b 3)) (= x (b 5))))
           (return x)))
    (return piece-blank)
))

(defun proc5() (prog (x)
    (setq x (b 5)) 
    (cond ((or (and (= x (b 3)) (= x (b 4)))
               (and (= x (b 2)) (= x (b 8))))
           (return x)))
    (return piece-blank)
))

(defun proc6() (prog (x)
    (setq x (b 6)) 
    (cond ((or (and (= x (b 7)) (= x (b 8)))
               (and (= x (b 0)) (= x (b 3)))
               (and (= x (b 4)) (= x (b 2))))
           (return x)))
    (return piece-blank)
))

(defun proc7() (prog (x)
    (setq x (b 7)) 
    (cond ((or (and (= x (b 6)) (= x (b 8)))
               (and (= x (b 1)) (= x (b 4))))
           (return x)))
    (return piece-blank)
))

(defun proc8() (prog (x)
    (setq x (b 8)) 
    (cond ((or (and (= x (b 6)) (= x (b 7)))
               (and (= x (b 2)) (= x (b 5)))
               (and (= x (b 0)) (= x (b 4))))
           (return x)))
    (return piece-blank)
))

(setq procs (hunk proc0 proc1 proc2 proc3 proc4 proc5 proc6 proc7 proc8))

(defun minmax (alpha beta depth move) (prog (i value score halt pieceMove nextDepth) ; this is how local variables are declared
    (setq moves (+ 1 moves))
    ;(princ board) (princ " ") (princ alpha) (princ " ") (princ beta) (princ " ") (princ move) (princ " ") (princ depth) (princ "\n")

    (cond ((> depth 3)
           ;(setq win (winner)) ; almost 2x slower than using procs
           (setq win (funcall (cxr move procs)))
           (cond ((= win piece-x) (return score-win))
                 ((= win piece-y) (return score-lose))
                 ((= depth 8) (return score-tie))
           ))
    )

    (cond ((evenp depth)
           (setq value score-max)
           (setq pieceMove piece-y))
          (t ; else
           (setq value score-min)
           (setq pieceMove piece-x))
    )

    (setq nextDepth (+ 1 depth))
    (setq i 0)
    _nexti_
    (cond ((= (b i) piece-blank)
           (rplacx i board pieceMove)
           (setq score (minmax alpha beta nextDepth i))
           (rplacx i board piece-blank)

           (cond ((oddp depth)
                  (cond ((= score score-win) 
                         (setq halt t)) ; return doesn't work in pc-lisp in this context (3 deep in cond)
                  )
                  (cond ((> score value)
                         (setq value score)
                         (cond ((>= value beta)
                                (setq halt t)))
                         (cond ((> value alpha)
                                (setq alpha value))))
                  ))
                 (t ; lisp for else
                  (cond ((= score score-lose) 
                         (setq halt t))
                  )
                  (cond ((< score value)
                         (setq value score)
                         (cond ((<= value alpha)
                                (setq halt t)))
                         (cond ((< value beta)
                                (setq beta value))))
                  ))
           ))
    )

    (cond ((and (not halt) (< i 8))
           (setq i (+ i 1))
           (go _nexti_))
    )

    (return value)
))

(defun runmm ( position )
    (rplacx position board piece-x)
    (minmax score-min score-max 0 position)
    (rplacx position board piece-blank)
)

; solve for each of the 3 unique (after reflections) opening moves
(runmm 0)
(runmm 1)
(runmm 4)

(princ "moves: ") (princ moves) (princ "\n") ; should be 6493

;(princ "memstat:         ") (princ (memstat)) (princ "\n")
;(gc)
;(princ "memstat post gc: ") (princ (memstat)) (princ "\n")

(exit)
