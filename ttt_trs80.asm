; trs-80 Model 100 app to prove you can't win at tic-tac-toe
; trs-80 specific constants

DISPLY  equ     05a58h  ; display string pointed to by hl
DISONE  equ     04b44h  ; display character in A
SECS    equ     0f933h  ; memory location for seconds (doesn't seem to work)
CHGET   equ     012cbh  ; get a character

ITERATIONS  equ       10   ; # of times to run (max 32767)
XSCO        equ        9   ; maximum score
NSCO        equ        2   ; minimum score
WSCO        equ        6   ; winning score
TSCO        equ        5   ; tie score
LSCO        equ        4   ; losing score
XPIECE      equ        1   ; X move piece
OPIECE      equ        2   ; Y move piece
BLANKPIECE  equ        0   ; empty piece
MINVALS     equ   00902h   ; xsco and opiece when minimizing
MAXVALS     equ   00201h   ; nsco and xpiece when maximizing

        aseg
        org     0c738h  ; 51000 decimal

        push    b
        push    d
        push    h
 
AGAIN:
        lxi     h, 0
        shld    MOVES               ; set to 0 each iteration to avoid overflow
        mvi     a, 0
        sta     V
        sta     I
        sta     SC
        sta     DEPTH
        sta     ALPHA
        sta     BETA

        mvi     a, 0                
        call    RUNMM               ; first of 3 unique board configurations

        mvi     a, 1
        call    RUNMM               ; second

        mvi     a, 4
        call    RUNMM               ; third
                                         
        lhld    ITERS               ; increment iteration count and loop until done
        inx     h
        shld    ITERS
        lxi     b, ITERATIONS
        mov     a, b
        cmp     h
        jnz     AGAIN
        mov     a, c
        cmp     l
        jnz     AGAIN

        lhld    MOVES
        call    PUTHL
        lxi     h, CRLF
        call    DISPLY
        
        pop     h
        pop     d
        pop     b

        ret

RUNMM:                              ; Run the MINMAX function for a given board
        push    a
        mov     d, a
        mvi     b, 0                ; store the first move
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        mvi     a, XPIECE
        stax    b

        mov     a, d                ; where the first move is: 0, 1, or 4
        mvi     d, NSCO             ; alpha
        mvi     e, XSCO             ; beta
        mvi     c, 0                ; depth
        call    MM_MIN

        pop     a
        mvi     b, 0                ; store the first move
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        mvi     a, BLANKPIECE
        stax    b
        ret

MM_MMAX:                            ; the recursive scoring function
        mov     b, a                ; save the move position
        mov     a, c                ; save depth, alpha, and beta from c, d, and e
        sta     DEPTH
        mov     l, d
        mov     h, e
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES
        inx     h
        shld    MOVES

        mov     a, c                ; # of pieces played so far == 1 + depth
        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      X_SKIPWIN

        mov     a, b                ; where the move was taken 0..8
        mvi     b, OPIECE           ; the piece that took the move
        call    CALLSCOREPROC       ; look for a winning position

        cpi     OPIECE              ; see if O won
        mvi     a, LSCO             ; losing score since O won
        rz

X_SKIPWIN:
        mvi     a, NSCO             ; maximizing odd depths
        sta     V

X_MMFOR:
        mvi     a, 0                ; the variable I will go from 0..8
        sta     I

X_MMLOOP:
        mvi     b, 0                ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        ldax    b
        cpi     0                   ; is the board space free?
        jnz     X_MMLEND

        mvi     a, XPIECE
        stax    b                   ; make the move
        push    b                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        lhld    ALPHA               ; alpha in l and beta in h
        push    h
        mov     d, l                ; alpha
        mov     e, h                ; beta
        lhld    I                   ; I in l and PM in h
        push    h
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     c, h                ; depth
        inr     c
        lda     I                   ; the move position

        ; D = alpha, E = beta, C = depth, A = return score

        call    MM_MIN
        sta     SC                  ; save the score

        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        mov     d, h                ; save DEPTH
        pop     h                   
        shld    I                   ; restore I and PM
        pop     h
        shld    ALPHA               ; restore ALPHA and BETA

        pop     b                   ; restore the 0 in the board where the turn was placed
        mvi     a, 0
        stax    b

        lda     SC                  ; maximize case
        cpi     WSCO                ; V - WSCO. If zero, can't do better.
        rz

        lda     SC
        mov     b, a
        lda     V
        cmp     b                   ; V - SC
        jp      X_MMNOMAX           ; jp is >= 0. The comparision is backwards due to no jle or jgz on 8080
        mov     a, b
        sta     V                   ; update V with the new best score
X_MMNOMAX:
        lda     ALPHA
        mov     b, a
        lda     V
        cmp     b                   ; V - ALPHA
        jm      X_MMNOALP
        sta     ALPHA               ; new alpha
X_MMNOALP:
        lda     BETA
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        jm      X_MMLEND
        lda     V
        ret                         ; Alpha pruning
X_MMLEND:
        lda     I
        inr     a
        sta     I
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      X_MMLOOP

        lda     V
        ret

MM_MIN:                             ; the recursive scoring function
        mov     b, a                ; save the move position
        mov     a, c                ; save depth, alpha, and beta from c, d, and e
        sta     DEPTH
        mov     l, d
        mov     h, e
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES
        inx     h
        shld    MOVES

        mov     a, c                ; # of pieces played so far == 1 + depth
        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      N_SKIPWIN

        mov     a, b                        ; where the move was taken 0..8
        mvi     b, XPIECE           ; the piece that took the move
        call    CALLSCOREPROC       ; look for a winning position

        cpi     XPIECE              ; see if X won
        mvi     a, WSCO             ; winning score. avoid branch by always loading
        rz

        lda     DEPTH               ; check if at the bottom of the recursion
        cpi     8
        mvi     a, TSCO             ; tie score. avoid branch by always loading
        rz

N_SKIPWIN:
        mvi     a, XSCO
        sta     V

N_MMFOR:
        mvi     a, 0                ; the variable I will go from 0..8
        sta     I

N_MMLOOP:
        mvi     b, 0                ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        ldax    b
        cpi     0                   ; is the board space free?
        jnz     N_MMLEND

        mvi     a, OPIECE           ; store the move on the board
        stax    b
        push    b                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        lhld    ALPHA               ; alpha in l and beta in h
        push    h
        mov     d, l                ; alpha
        mov     e, h                ; beta
        lhld    I                   ; I in l and PM in h
        push    h
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     c, h                ; depth
        inr     c
        lda     I                   ; the move position

        ; D = alpha, E = beta, C = depth, A = return score

        call    MM_MMAX
        sta     SC                  ; save the score

        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        mov     d, h                ; save DEPTH
        pop     h                   
        shld    I                   ; restore I and PM
        pop     h
        shld    ALPHA               ; restore ALPHA and BETA

        pop     b                   ; restore the 0 in the board where the turn was placed
        mvi     a, 0
        stax    b

        lda     SC
        cpi     LSCO                ; V - LSCO. If zero, can't do worse.
        rz

        lda     V
        mov     b, a
        lda     SC
        cmp     b                   ; SC - V
        jp      N_MMNOMIN
        sta     V
N_MMNOMIN:
        lda     BETA
        mov     b, a
        lda     V
        cmp     b                   ; V - Beta
        jp      N_MMNOBET
        sta     BETA                ; new beta
N_MMNOBET:
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        lda     V                   ; potentially wasted load, but saves a branch
        rp                          ; Beta pruning
N_MMLEND:
        lda     I
        inr     a
        sta     I
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      N_MMLOOP

        lda     V
        ret

NEGHL:                              ; negate hl via twos complement xx complement + 1
        mov     a, h
        cma
        mov     h, a
        mov     a, l
        cma
        mov     l, a
        inx     h
        ret

PUTHL:
        mov     a, h                ; Get the sign bit of the integer,
        ral                         ; which is the top bit of the high byte
        sbb     a                   ; A=00 if positive, FF if negative
        sta     NEGF                ; Store it as the negative flag
        cnz     NEGHL               ; And if HL was negative, make it positive
        lxi     d, NUM              ; Load pointer to end of number string
        push    d                   ; Onto the stack
        lxi     b, -10              ; Divide by ten (by trial subtraction)
DIGIT:
        lxi     d, -1               ; DE = quotient. There is no 16-bit subtraction,
DGTDIV:
        dad     b                   ; so we just add a negative value,
        inx     d                   
        jc      DGTDIV              ; while that overflows.
        mvi     a, '0' + 10         ; The loop runs once too much so we're 10 out
        add     l                   ; The remainder (minus 10) is in L
        xthl                        ; Swap HL with top of stack (i.e., the string pointer)
        dcx     h                   ; Go back one byte
        mov     m, a                ; And store the digit
        xthl                        ; Put the pointer back on the stack
        xchg                        ; Do all of this again with the quotient
        mov     a, h                ; If it is zero, we're done
        ora     l
        jnz     DIGIT               ; But if not, there are more digits
        pop     d                   ; Put the string pointer from the stack in DE
        lda     NEGF                ; See if the number was supposed to be negative
        inr     a                   
        mov     h, d
        mov     l, e
        jnz     DISPLY              ; positive number. return from DISPLY returns from here
        dcx     d                   ; But if so, we need to add a minus in front
        mvi     a, '-'              
        stax    d                   
        mov     h, d
        mov     l, e
        jmp     DISPLY              ; And only then print the string. bdos will return to caller

CALLSCOREPROC:
        push     b                  ; save the piece that took the move for later

        add      a                  ; double the move position because function pointers are two bytes
        lxi      b, callAddress
        inx      b                  ; get past the call instruction to the address
        lxi      h, WINPROCS
        mov      e, a
        mvi      d, 0
        dad      d
        xchg

        ; now read the function pointer and patch the instructions we're about to execute
        ldax     d  
        stax     b
        inx      b
        inx      d
        ldax     d
        stax     b

        pop      a                  ; the piece that took the move

callAddress:
        call     PUTHL              ; Not really. call function address written in the code stream
        ret

proc0:
        lxi      h, BOARD + 1
        cmp      m
        jnz      proc0nextwin
        lxi      h, BOARD + 2
        cmp      m
        rz

proc0nextwin:
        lxi      h, BOARD + 3
        cmp      m
        jnz      proc0nextwin2
        lxi      h, BOARD + 6
        cmp      m
        rz

proc0nextwin2:
        lxi      h, BOARD + 4
        cmp      m
        jnz      proc0no
        lxi      h, BOARD + 8
        cmp      m
        rz

proc0no:
        mvi      a, 0
        ret
        
proc1:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc1nextwin
        lxi      h, BOARD + 2
        cmp      m
        rz

proc1nextwin:
        lxi      h, BOARD + 4
        cmp      m
        jnz      proc1no
        lxi      h, BOARD + 7
        cmp      m
        rz

proc1no:
        mvi      a, 0
        ret
        
proc2:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc2nextwin
        lxi      h, BOARD + 1
        cmp      m
        rz

proc2nextwin:
        lxi      h, BOARD + 5
        cmp      m
        jnz      proc2nextwin2
        lxi      h, BOARD + 8
        cmp      m
        rz

proc2nextwin2:
        lxi      h, BOARD + 4
        cmp      m
        jnz      proc2no
        lxi      h, BOARD + 6
        cmp      m
        rz

proc2no:
        mvi      a, 0
        ret
        
proc3:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc3nextwin
        lxi      h, BOARD + 6
        cmp      m
        rz

proc3nextwin:
        lxi      h, BOARD + 4
        cmp      m
        jnz      proc3no
        lxi      h, BOARD + 5
        cmp      m
        rz

proc3no:
        mvi      a, 0
        ret
        
proc4:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc4nextwin
        lxi      h, BOARD + 8
        cmp      m
        rz

proc4nextwin:
        lxi      h, BOARD + 2
        cmp      m
        jnz      proc4nextwin2
        lxi      h, BOARD + 6
        cmp      m
        rz

proc4nextwin2:
        lxi      h, BOARD + 1
        cmp      m
        jnz      proc4nextwin3
        lxi      h, BOARD + 7
        cmp      m
        rz

proc4nextwin3:
        lxi      h, BOARD + 3
        cmp      m
        jnz      proc4no
        lxi      h, BOARD + 5
        cmp      m
        rz

proc4no:
        mvi      a, 0
        ret

proc5:
        lxi      h, BOARD + 3
        cmp      m
        jnz      proc5nextwin
        lxi      h, BOARD + 4
        cmp      m
        rz

proc5nextwin:
        lxi      h, BOARD + 2
        cmp      m
        jnz      proc5no
        lxi      h, BOARD + 8
        cmp      m
        rz

proc5no:
        mvi      a, 0
        ret

proc6:
        lxi      h, BOARD + 4
        cmp      m
        jnz      proc6nextwin
        lxi      h, BOARD + 2
        cmp      m
        rz

proc6nextwin:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc6nextwin2
        lxi      h, BOARD + 3
        cmp      m
        rz

proc6nextwin2:
        lxi      h, BOARD + 7
        cmp      m
        jnz      proc6no
        lxi      h, BOARD + 8
        cmp      m
        rz

proc6no:
        mvi      a, 0
        ret
        
proc7:
        lxi      h, BOARD + 1
        cmp      m
        jnz      proc7nextwin
        lxi      h, BOARD + 4
        cmp      m
        rz

proc7nextwin:
        lxi      h, BOARD + 6
        cmp      m
        jnz      proc7no
        lxi      h, BOARD + 8
        cmp      m
        rz

proc7no:
        mvi      a, 0
        ret
        
proc8:
        lxi      h, BOARD + 0
        cmp      m
        jnz      proc8nextwin
        lxi      h, BOARD + 4
        cmp      m
        rz

proc8nextwin:
        lxi      h, BOARD + 2
        cmp      m
        jnz      proc8nextwin2
        lxi      h, BOARD + 5
        cmp      m
        rz

proc8nextwin2:
        lxi      h, BOARD + 6
        cmp      m
        jnz      proc8no
        lxi      h, BOARD + 7
        cmp      m
        rz

proc8no:
        mvi      a, 0
        ret

WINPROCS: dw    proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

        
NEGF:   db      0                   ; Space for negative flag
        db      '-00000'            
NUM:    db      0                   ; trs-80 strings are null-terminated
STRWIN: db      'winner ', 0
CRLF:   db      10,13,0
BOARD:  db      0,0,0,0,0,0,0,0,0
SC:     db      0                   ; score in MinMax
I:      db      0                   ; Index in 0..8 loop in MinMax
PM:     db      0                   ; Unused for now. must be after I
V:      db      0                   ; value in minmax
DEPTH:  db      0                   ; current depth of recursion. must be after V
ALPHA:  db      0                   ; Alpha in a/b pruning
BETA:   db      0                   ; Beta in a/b pruning. must be after ALPHA
MOVES:  dw      0                   ; Count of moves examined (to validate the app)
ITERS:  dw      0                   ; iterations of running the app

        end
