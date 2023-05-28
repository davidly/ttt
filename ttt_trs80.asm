; trs-80 Model 100 app to prove you can't win at tic-tac-toe
; trs-80 specific constants

DISPLY  equ     05a58h  ; display string pointed to by hl
DISONE  equ     04b44h  ; display character in A
SECS    equ     0f933h  ; memory location for seconds (doesn't seem to work)
CHGET   equ     012cbh  ; get a character

ITERATIONS  equ      100   ; # of times to run (max 32767)
XSCO        equ        9   ; maximum score
NSCO        equ        2   ; minimum score
WSCO        equ        6   ; winning score
TSCO        equ        5   ; tie score
LSCO        equ        4   ; losing score
XPIECE      equ        1   ; X move piece
OPIECE      equ        2   ; Y move piece
BLANKPIECE  equ        0   ; empty move piece

        aseg
        org     0c738h  ; 51000 decimal
        
AGAIN:
        lxi     h, 0
        shld    MOVES               ; set to 0 each iteration to avoid overflow
        mvi     a, 0
        sta     V
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
        
        ret

RUNMM:                              ; Run the MINMAX function for a given board
                                    ; D = alpha, E = beta, C = depth
        mvi     b, 0                ; store the first move
        mov     c, a
        lxi     h, BOARD
        dad     b
        mvi     m, XPIECE
        push    h                   ; save the pointer to the move location for later

        xra     a                   ; depth
        mov     b, c                ; move position
        mvi     l, NSCO             ; alpha
        mvi     h, XSCO             ; beta
        call    MM_MIN

        pop     h                   ; restore the move location
        mvi     m, BLANKPIECE       ; restore a blank on the board

        ret

MM_MAX:                             ; the recursive scoring function
        sta     DEPTH
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES               ; no 16-bit memory increment, so load in hl for that
        inx     h
        shld    MOVES

        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      X_SKIPWIN

        mov     a, b                ; where the move was taken 0..8
        mvi     b, OPIECE           ; the piece that took the move
        call    CALLSCOREPROC       ; look for a winning position

        cpi     OPIECE              ; see if O won
        mvi     a, LSCO             ; losing score since O won
        rz

X_SKIPWIN:
        mvi     a, NSCO             ; maximizing odd depths, so start with minimum score
        sta     V
        lxi     d, 0                ; the variable I will go from 0..8

X_MMLOOP:
        lxi     h, BOARD
        dad     d
        xra     a                   ; BLANKPIECE is 0
        cmp     m
        jnz     X_MMLEND

        mvi     m, XPIECE           ; make the move
        push    h                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        push    d                   ; save i in the for loop
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     b, e                ; board position of the latest move
        mov     a, h                ; depth
        inr     a
        lhld    ALPHA               ; alpha in l and beta in h
        push    h

        ; C = depth, B = move position, L = alpha, H = beta  ====> A = return score

        call    MM_MIN
        
        pop     h
        shld    ALPHA               ; restore ALPHA and BETA
        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        pop     d                   ; restore i in the for loop

        pop     h
        mvi     m, BLANKPIECE       ; restore the 0 on the board where the turn was placed

        cpi     WSCO                ; SC - WSCO. If zero, can't do better.
        rz

        mov     b, a
        lxi     h, V                
        mov     a, m
        cmp     b                   ; V - SC
        jp      X_MMNOMAX           ; jp is >= 0. The comparision is backwards due to no jle or jgz on 8080
        mov     m, b                ; update V with the new best score

X_MMNOMAX:
        mov     a, m                ; load latest V
        lxi     h, ALPHA
        cmp     m                   ; V - ALPHA
        jm      X_MMNOALP
        mov     m, a                ; new alpha
        
X_MMNOALP:
        lda     BETA
        cmp     m                   ; Beta - Alpha
        jz      X_MMPRUNE           ; there is no jump if > 0
        jp      X_MMLEND            ; Alpha pruning

X_MMPRUNE:
        lda     V
        ret                         ; Alpha pruning        

X_MMLEND:
        inr     e
        mov     a, e
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      X_MMLOOP

        lda     V
        ret

MM_MIN:                             ; the recursive scoring function
        sta     DEPTH
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES               ; no 16-bit memory increment, so load in hl for that
        inx     h
        shld    MOVES

        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      N_SKIPWIN

        mov     a, b                ; where the move was taken 0..8
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
        lxi     d, 0                ; the variable I will go from 0..8
        
N_MMLOOP:
        lxi     h, BOARD
        dad     d
        xra     a                   ; BLANKPIECE is 0
        cmp     m
        jnz     N_MMLEND

        mvi     m, OPIECE           ; make the move
        push    h                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        push    d                   ; save i in the for loop
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     b, e                ; board position of the latest move
        mov     a, h                ; depth
        inr     a
        lhld    ALPHA               ; alpha in l and beta in h
        push    h

        ; A = depth, B = move position, L = alpha, H = beta  ====> A = return score

        call    MM_MAX

        pop     h
        shld    ALPHA               ; restore ALPHA and BETA
        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        pop     d                   ; restore i in the for loop

        pop     h
        mvi     m, BLANKPIECE       ; restore the 0 on the board where the turn was placed

        cpi     LSCO                ; SC - LSCO. If zero, can't do worse.
        rz

        lxi     h, V                
        cmp     m                   ; SC - V
        jp      N_MMNOMIN
        mov     m, a

N_MMNOMIN:
        mov     a, m                ; load latest V
        lxi     h, BETA
        cmp     m                   ; V - Beta
        jp      N_MNOBET
        mov     m, a                ; new beta

N_MNOBET:
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        lda     V                   ; potentially wasted load, but saves a branch
        rp                          ; Beta pruning

N_MMLEND:
        inr     e
        mov     a, e
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

; a = the proc to call 0..8
; b = the player who just took a move, O or X
CALLSCOREPROC:
        add      a                  ; double the move position because function pointers are two bytes
        lxi      h, WINPROCS        ; load the pointer to the list of function pointers 0..8
        mov      e, a               ; prepare to add
        mvi      d, 0
        dad      d                  ; hl = de + hl
        xchg                        ; exchange de and hl
        ldax     d                  ; load the low byte of procX
        mov      l, a
        inx      d
        ldax     d                  ; load the hight byte of procX
        mov      h, a
        mov      a, b               ; put the player move (X or O) in a
        pchl                        ; move the winner proc address from hl to pc (jump to it)

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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
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
        xra      a
        ret

WINPROCS: dw    proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

        
NEGF:   db      0                   ; Space for negative flag
        db      '-00000'            
NUM:    db      0                   ; trs-80 strings are null-terminated
STRWIN: db      'winner ', 0
CRLF:   db      10,13,0
BOARD:  db      0,0,0,0,0,0,0,0,0
V:      db      0                   ; value in minmax
DEPTH:  db      0                   ; current depth of recursion. must be after V
ALPHA:  db      0                   ; Alpha in a/b pruning
BETA:   db      0                   ; Beta in a/b pruning. must be after ALPHA
MOVES:  dw      0                   ; Count of moves examined (to validate the app)
ITERS:  dw      0                   ; iterations of running the app

        end
