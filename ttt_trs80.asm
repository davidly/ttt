; trs-80 specific constants

DISPLY  equ     05a58h  ; display string pointed to by hl
DISONE  equ     04b44h  ; display character in A
SECS    equ     0f933h  ; memory location for seconds (doesn't seem to work)
CHGET   equ     012cbh  ; get a character

ITERATIONS  equ   100   ; # of times to run (max 32767)
XSCO        equ     9   ; maximum score
NSCO        equ     2   ; minimum score
WSCO        equ     6   ; winning score
TSCO        equ     5   ; tie score
LSCO        equ     4   ; losing score
XPIECE      equ     1   ; X move piece
OPIECE      equ     2   ; Y move piece


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
        sta     PM
        sta     DEPTH
        sta     ALPHA
        sta     BETA

        mvi     a, 1                
        sta     BOARD
        call    RUNMM               ; first of 3 unique board configurations
        mvi     a, 0 
        sta     BOARD

        mvi     a, 1
        sta     BOARD + 1
        call    RUNMM               ; second
        mvi     a, 0
        sta     BOARD + 1

        mvi     a, 1
        sta     BOARD + 4
        call    RUNMM               ; third
        mvi     a, 0
        sta     BOARD + 4
                                 
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
        mvi     d, NSCO		        ; alpha
        mvi     e, XSCO		        ; beta
        mvi     c, 0		        ; depth
        call    MINMAX
        ret

MINMAX:                             ; the recursive scoring function
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
        jm      SKIPWIN

        call    WINNER              ; look for a winning position

        cpi     0                   ; was there a winner?
        jz      CHKDEPTH

        cpi     XPIECE              ; see if X won
        mvi     a, WSCO             ; winning score. avoid branch by always loading
        rz

        mvi     a, LSCO             ; losing score since O won
        ret

CHKDEPTH:
        lda     DEPTH               ; check if at the bottom of the recursion
        cpi     8
        mvi     a, TSCO             ; tie score. avoid branch by always loading
        rz

SKIPWIN:
        lda     DEPTH               ; min/max check
        ani     1
        jz      MMMIN        

        mvi     a, NSCO             ; maximizing odd depths
        sta     V
        mvi     a, XPIECE
        sta     PM
        jmp     MMFOR

MMMIN:
        mvi     a, XSCO
        sta     V
        mvi     a, OPIECE
        sta     PM

MMFOR:
        mvi     a, 0                ; the variable I will go from 0..8
        sta     I

MMLOOP:
        mvi     b, 0                ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        ldax    b
        cpi     0                   ; is the board space free?
        jnz     MMLEND

        lda     PM                  ; store the current Piece Move in the free spot
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
        
        ; D = alpha, E = beta, C = depth, A = return score

        call    MINMAX
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

MMENDD:
        mov     a, d                ; is the depth odd/even: max/min
        ani     1
        jz      MMSMIN              ; min/max check

        lda     SC                  ; maximize case
        cpi     WSCO                ; V - WSCO. If zero, can't do better.
        rz

        lda     SC
        mov     b, a
        lda     V
        cmp     b                   ; V - SC
        jp      MMNOMAX             ; jp is >= 0. The comparision is backwards due to no jle or jgz on 8080
        mov     a, b
        sta     V                   ; update V with the new best score
MMNOMAX:
        lda     ALPHA
        mov     b, a
        lda     V
        cmp     b                   ; V - ALPHA
        jm      MMNOALP
        sta     ALPHA               ; new alpha
MMNOALP:
        lda     BETA
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        jm      MMLEND
        lda     V
        ret                         ; Alpha pruning
MMSMIN:                             ; minimize case
        lda     SC
        cpi     LSCO                ; V - LSCO. If zero, can't do worse.
        rz

        lda     V
        mov     b, a
        lda     SC
        cmp     b                   ; SC - V
        jp      MMNOMIN
        sta     V
MMNOMIN:
        lda     BETA
        mov     b, a
        lda     V
        cmp     b                   ; V - Beta
        jp      MMNOBET
        sta     BETA                ; new beta
MMNOBET:
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        lda     V                   ; potentially wasted load, but saves a branch
        rp                          ; Beta pruning
MMLEND:
        lda     I
        inr     a
        sta     I
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      MMLOOP

        lda     V
        ret

WINNER: ; returns winner ( 0 = TIE, 1 = X, 2 = O ) in register a
        ;  0 1 2
        ;  3 4 5
        ;  6 7 8
        lda     BOARD
L05005:
        cpi     0
        jz      L05020

L05010:
        lxi     h, BOARD + 1
        cmp     m
        jnz     L05015
        lxi     h, BOARD + 2
        cmp     m
        rz

L05015:
        lxi     h, BOARD + 3
        cmp     m
        jnz     L05020
        lxi     h, BOARD + 6
        cmp     m
        rz

L05020:
        lda     BOARD + 3
        cpi     0
        jz      L05025
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05025
        lxi     h, BOARD + 5
        cmp     m
        rz

L05025:
        lda     BOARD + 6
        cpi     0
        jz      L05030
        lxi     h, BOARD + 7
        cmp     m
        jnz     L05030
        lxi     h, BOARD + 8
        cmp     m
        rz

L05030:
        lda     BOARD + 1
        cpi     0
        jz      L05035
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05035
        lxi     h, BOARD + 7
        cmp     m
        rz

L05035:
        lda     BOARD + 2
        cpi     0
        jz      L05040
        lxi     h, BOARD + 5
        cmp     m
        jnz     L05040
        lxi     h, BOARD + 8
        cmp     m
        rz

L05040:
        lda     BOARD
        cpi     0
        jz      L05045
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05045
        lxi     h, BOARD + 8
        cmp     m
        rz

L05045:
        lda     BOARD + 2
        cpi     0
        rz      
        lxi     h, BOARD + 4
        cmp     m
        jnz     WINONE
        lxi     h, BOARD + 6
        cmp     m
        rz
        
WINONE:
        mvi     a, 0                ; no winning piece
        ret        

NEGHL:                              ; negate hl via twos complement -- complement + 1
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
        
NEGF:   db      0                   ; Space for negative flag
        db      '-00000'            
NUM:    db      0                   ; rs-80 strings are null-terminated
STRWIN: db      'winner ', 0
CRLF:   db      10,13,0
BOARD:  db      0,0,0,0,0,0,0,0,0
SC:     db      0                   ; score in MinMax
I:      db      0                   ; Index in 0..8 loop in MinMax
PM:     db      0                   ; piece move -- current move in MinMax. must be after I
V:      db      0                   ; value in minmax
DEPTH:  db      0                   ; current depth of recursion. must be after V
ALPHA:  db      0                   ; Alpha in a/b pruning
BETA:   db      0                   ; Beta in a/b pruning. must be after ALPHA
MOVES:  dw      0                   ; Count of moves examined (to validate the app)
ITERS:  dw      0                   ; iterations of running the app


        end
