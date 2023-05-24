; i8080 version of an app that proves you can't win at tic-tac-toe
;
; copy / assemble, link, and run on cp/m using:
; r tttcpm.asm      -- cp/m emulators sometimes allow reading files like this.
; asm tttcpm
; load tttcpm
; tttcpm
;
; The board positions:
;   0 1 2
;   3 4 5
;   6 7 8
;
; Runs faster with USEWINPROCS equ 1

; cp/m-specific constants

BDOS EQU  5
WCONF EQU 2
PRSTR EQU 9

USEWINPROCS equ     1     ; optimization 1 means use function pointers or 0 means use winner procedure
ITERATIONS  equ     1000  ; # of times to run (max 32767)
XSCO        equ     9     ; maximum score
NSCO        equ     2     ; minimum score
WSCO        equ     6     ; winning score
TSCO        equ     5     ; tie score
LSCO        equ     4     ; losing score
XPIECE      equ     1     ; X move piece
OPIECE      equ     2     ; Y move piece
BLANKPIECE  equ     0     ; empty move piece

org     100H
  AGAIN:
        lxi     h, 0
        shld    MOVES               ; set to 0 each iteration to avoid overflow
        mvi     a, 0
        sta     V
        sta     I
        sta     DEPTH
        sta     ALPHA
        sta     BETA

        mvi     a, 0                
        call    RunMinMax           ; first of 3 unique board configurations

        mvi     a, 1
        call    RunMinMax           ; second

        mvi     a, 4
        call    RunMinMax           ; third
                                 
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

        lxi     h, STRMOVES
        call    DISPLY
        lhld    MOVES
        call    PUTHL
        lxi     h, CRLF
        call    DISPLY

        lxi     h, STRITERS
        call    DISPLY
        lxi     h, ITERATIONS
        call    PUTHL
        lxi     h, CRLF
        call    DISPLY

        jmp 0                       ; cp/m call to terminate the app

DisplayOneCharacter:                ; display the character in a
        push    b
        push    d
        push    h

        mvi     c, WCONF
        mov     e, a
        call    BDOS

        pop     h
        pop     d
        pop     b
        ret

DisplayDigit:                       ; Argument # 0-9 is in register B
        push    b
        push    d
        push    h

        mvi     a, 48
        add     b
        call    DisplayOneCharacter

        pop     h
        pop     d
        pop     b
        ret

RunMinMax:                          ; Run the MINMAX function for a given first move
        mvi     b, 0                ; store the first move
        mov     c, a
        lxi     h, BOARD
        dad     b
        mvi     m, XPIECE
        push    h                   ; save the pointer to the move location for later

        mvi     d, NSCO             ; alpha
        mvi     e, XSCO             ; beta
        mvi     c, 0                ; depth
        call    MinMaxMinimize

        pop     h                   ; restore the move location
        mvi     m, BLANKPIECE       ; restore a blank on the board

        ret

; The 8080 has no simple way to address arguments or local variables relative to sp.
; The approach here is to:
;   1) pass arguments in a, c, d, and e (move position, depth, alpha, and beta respectively)
;   2) store the arguments in global variables so they are easy to access
;   3) when making a call, push the global variables on the stack
;   4) when returning froma call, restore the global variables with popped stack values
;   5) for tail functions, just pass arguments in registers with no stack or global usage for arguments
; The extra copies to/from globals are expensive, but overall faster since accessing them is fast.

MinMaxMaximize:                     ; the recursive scoring function
IF USEWINPROCS
        mov     b, a                ; save where the move was taken
ENDIF
        mov     a, c                ; save depth, alpha, and beta from c, d, and e
        sta     DEPTH
        mov     l, d
        mov     h, e
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES               ; no 16-bit memory increment, so load in hl for that
        inx     h
        shld    MOVES

        mov     a, c                ; # of pieces played so far == 1 + depth
        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      MAX$SKIPWIN

IF USEWINPROCS
        mov     a, b                ; where the move was taken 0..8
        mvi     b, OPIECE           ; the piece that took the move
        call    CallScoreProc       ; look for a winning position
ENDIF
IF NOT USEWINPROCS
        call    WINNER              ; look for a winning position
ENDIF

        cpi     OPIECE              ; see if O won
        mvi     a, LSCO             ; losing score since O won
        rz

  MAX$SKIPWIN:
        mvi     a, NSCO             ; maximizing odd depths
        sta     V
        mvi     a, 0                ; the variable I will go from 0..8
        sta     I

  MAX$MMLOOP:
        mvi     b, 0                ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     a, m
        cpi     BLANKPIECE          ; is the board space free?
        jnz     MAX$MMLEND

        mvi     m, XPIECE           ; make the move
        push    h                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        lhld    ALPHA               ; alpha in l and beta in h
        push    h
        mov     d, l                ; alpha
        mov     e, h                ; beta
        lhld    I                   ; I in l and (unused) in h
        push    h
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     c, h                ; depth
        inr     c
IF USEWINPROCS
        lda     I                   ; the move position
ENDIF

        ; A = Move position, D = alpha, E = beta, C = depth  ====> A = return score

        call    MinMaxMinimize

        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        mov     d, h                ; save DEPTH
        pop     h                   
        shld    I                   ; restore I and (unused)
        pop     h
        shld    ALPHA               ; restore ALPHA and BETA

        pop     h
        mvi     m, BLANKPIECE       ; restore the 0 in the board where the turn was placed

        cpi     WSCO                ; SC - WSCO. If zero, can't do better.
        rz

        mov     b, a
        lda     V
        cmp     b                   ; V - SC
        jp      MAX$MMNOMAX         ; jp is >= 0. The comparision is backwards due to no jle or jgz on 8080
        mov     a, b
        sta     V                   ; update V with the new best score
  MAX$MMNOMAX:
        lda     ALPHA
        mov     b, a
        lda     V
        cmp     b                   ; V - ALPHA
        jm      MAX$MMNOALP
        sta     ALPHA               ; new alpha
  MAX$MMNOALP:
        lda     BETA
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        jm      MAX$MMLEND
        lda     V
        ret                         ; Alpha pruning
  MAX$MMLEND:
        lda     I
        inr     a
        sta     I
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      MAX$MMLOOP

        lda     V
        ret

MinMaxMinimize:                     ; the recursive scoring function
IF USEWINPROCS
        mov     b, a                ; save where the move was taken
ENDIF
        mov     a, c                ; save depth, alpha, and beta from c, d, and e
        sta     DEPTH
        mov     l, d
        mov     h, e
        shld    ALPHA               ; write alpha and beta

        lhld    MOVES               ; no 16-bit memory increment, so load in hl for that
        inx     h
        shld    MOVES

        mov     a, c                ; # of pieces played so far == 1 + depth
        cpi     4                   ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      MIN$SKIPWIN

IF USEWINPROCS
        mov     a, b                ; where the move was taken 0..8
        mvi     b, XPIECE           ; the piece that took the move
        call    CallScoreProc       ; look for a winning position
ENDIF
IF NOT USEWINPROCS
        call    WINNER              ; look for a winning position
ENDIF

        cpi     XPIECE              ; see if X won
        mvi     a, WSCO             ; winning score. avoid branch by always loading
        rz

        lda     DEPTH               ; check if at the bottom of the recursion
        cpi     8
        mvi     a, TSCO             ; tie score. avoid branch by always loading
        rz

  MIN$SKIPWIN:
        mvi     a, XSCO
        sta     V
        mvi     a, 0                ; the variable I will go from 0..8
        sta     I

  MIN$MMLOOP:
        mvi     b, 0                ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     a, m
        cpi     BLANKPIECE          ; is the board space free?
        jnz     MIN$MMLEND

        mvi     m, OPIECE           ; make the move
        push    h                   ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        lhld    ALPHA               ; alpha in l and beta in h
        push    h
        mov     d, l                ; alpha
        mov     e, h                ; beta
        lhld    I                   ; I in l and (unused) in h
        push    h
        lhld    V                   ; V in l and DEPTH in h
        push    h
        mov     c, h                ; depth
        inr     c
IF USEWINPROCS
        lda     I                   ; the move position
ENDIF        
        ; A = Move position, D = alpha, E = beta, C = depth  ====> A = return score

        call    MinMaxMaximize

        pop     h                   ; restore state after recursion
        shld    V                   ; restore V and DEPTH
        mov     d, h                ; save DEPTH
        pop     h                   
        shld    I                   ; restore I and (unused)
        pop     h
        shld    ALPHA               ; restore ALPHA and BETA

        pop     h
        mvi     m, BLANKPIECE       ; restore the 0 in the board where the turn was placed

        cpi     LSCO                ; SC - LSCO. If zero, can't do worse.
        rz

        mov     c, a
        lda     V                   ; check if we should update V with SC
        mov     b, a
        mov     a, c
        
        cmp     b                   ; SC - V
        jp      MIN$MMNOMIN
        sta     V
  MIN$MMNOMIN:
        lda     BETA
        mov     b, a
        lda     V
        cmp     b                   ; V - Beta
        jp      MIN$MMNOBET
        sta     BETA                ; new beta
  MIN$MMNOBET:
        mov     b, a
        lda     ALPHA
        cmp     b                   ; Alpha - Beta
        lda     V                   ; potentially wasted load, but saves a branch
        rp                          ; Beta pruning
  MIN$MMLEND:
        lda     I
        inr     a
        sta     I
        cpi     9                   ; a - 9.  Want to loop for 0..8
        jm      MIN$MMLOOP

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

DISPLY:                             ; display null-terminated string pointed to by hl
        push    h
        push    d
        push    b

        mov     b, h
        mov     c, l

  DNEXT:
        ldax    b
        cpi     0
        jz      DDONE
        call    DisplayOneCharacter
        inx     b
        jmp     DNEXT

  DDONE:
        pop     b
        pop     d
        pop     h
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
        mvi     a, '0'+10           ; The loop runs once too much so we're 10 out
        add     l                   ; The remainder (minus 10) is in L
        xthl                        ; Swap HL with top of stack (i.e., the string pointer)
        dcx     h                   ; Go back one byte
        mov     m, a                ; And store the digit
        xthl                        ; Put the pointer back on the stack
        xchg                        ; Do all of this again with the quotient
        mov     a, h                ; If it is zero, we're done
        ora     l
        jnz     DIGIT               ; But if not, there are more digits
        mvi     c, PRSTR            ; Prepare to call CP/M and print the string
        pop     d                   ; Put the string pointer from the stack in DE
        lda     NEGF                ; See if the number was supposed to be negative
        inr     a                   
        jnz     bdos                ; If not, print the string we have and return
        dcx     d                   ; But if so, we need to add a minus in front
        mvi     a, '-'              
        stax    d                   
        jmp     bdos                ; And only then print the string. bdos will return to caller

IF USEWINPROCS

; a = the proc to call 0..8
; b = the player who just took a move, O or X
CallScoreProc:
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

ENDIF
                                    
NEGF:     db      0                   ; Space for negative flag
          db      '-00000'            
NUM:      db      '$'                 ; Space for number. cp/m strings end with a dollar sign
CRLF:     db      10,13,0
STRITERS: db     'iterations: ', 0
STRMOVES: db     'moves: ', 0
BOARD:    db      0,0,0,0,0,0,0,0,0
I:        db      0                   ; Index in 0..8 loop in MinMax
UNUSED:   db      0                   ; unused variable. must be after I
V:        db      0                   ; value in minmax
DEPTH:    db      0                   ; current depth of recursion. must be after V
ALPHA:    db      0                   ; Alpha in a/b pruning
BETA:     db      0                   ; Beta in a/b pruning. must be after ALPHA
MOVES:    dw      0                   ; Count of moves examined (to validate the app)
ITERS:    dw      0                   ; iterations of running the app

end

