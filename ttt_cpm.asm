;
; copy / assemble, link, and run on cp/m using:
; r tttcpm.asm
; asm tttcpm
; load tttcpm
; tttcpm


BDOS EQU 5
WCONF EQU 2

XSCO    equ     9       ; maximum score
NSCO    equ     2       ; minimum score
WSCO    equ     6       ; winning score
TSCO    equ     5       ; tie score
LSCO    equ     4       ; losing score
XPIECE  equ     1       ; X move piece
OPIECE  equ     2       ; Y move piece

        org     100H

        push    b
        push    d
        push    h

;        mvi     c, WCONF
;        mvi     e, '$'
;        call    BDOS

;        mvi     a, 'a'
;        call    DISONE

AGAIN:
        lhld    0
        shld    MOVES           ; set to 0 each iteration to avoid overflow
        mvi     a, 0
        sta     V
        sta     I
        sta     SC
        sta     PM
        sta     DEPTH
        sta     ALPHA
        sta     BETA

        mvi     a, 0
        sta     BOARD
        sta     BOARD + 1
        sta     BOARD + 2
        sta     BOARD + 3
        sta     BOARD + 4
        sta     BOARD + 5
        sta     BOARD + 6
        sta     BOARD + 7
        sta     BOARD + 8
        sta     MOVES
        sta     MOVES + 1

        mvi     a, 1             ; First of 3 unique board configurations
        sta     BOARD
        call    RUNMM

        mvi     a, 0             ; Second
        sta     BOARD
        mvi     a, 1
        sta     BOARD + 1
        call    RUNMM
   
        mvi     a, 0             ; Third
        sta     BOARD + 1
        mvi     a, 1
        sta     BOARD + 4
        call    RUNMM
                                 
        lhld    MOVES
        call    DIHEX
        lxi     h, CRLF
        call    DISPLY

        lda     ITERS
        inr     a
        sta     ITERS
        cpi     10
        jnz     AGAIN

        pop     h
        pop     d
        pop     b

        jmp 0
        ret

CRLF:   db      10,13,0
STRWIN: db      'w', 'i', 'n', 'n', 'e', 'r', ' ', 0
BOARD:  db      0,0,0,0,0,0,0,0,0
STRHEX: db      0,0,0,0,0,0,0,0,0
V:      db      0      ; value in minmax
I:      db      0      ; Index in 0..8 loop in MinMax
SC:     db      0      ; score in MinMax
PM:     db      0      ; piece move -- current move in MinMax
DEPTH:  db      0      ; current depth of recursion
ALPHA:  db      0      ; Alpha in a/b pruning
BETA:   db      0      ; Beta in a/b pruning
MOVES:  db      0, 0   ; Count of moves examined (to validate the app)
ITERS:  db      0      ; iterations of running the app

DISONE:                  ; display the character in a
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

DISDIG:                  ; Argument # 0-9 is in register B
        push    b
        push    d
        push    h

        mvi     a, 48
        add     b
        call    DISONE

        pop     h
        pop     d
        pop     b
        ret

RUNMM:               ; Run the MINMAX function for a given board
                     ; D = alpha, E = beta, C = depth
        mvi     d, NSCO
        mvi     e, XSCO
        mvi     c, 0
        
        call    MINMAX
        mov     b,a

        ; display the winner (whould should always be 5 / TSCO / tie score
        ; comment out for now because it works
;        lxi     h, STRWIN
;        call    DISPLY
;        call    DISDIG
;        lxi     h, CRLF
;        call    DISPLY

        ret

INCMC                    ; increment move count
        push    h

        lhld    MOVES
        inx     h
        shld    MOVES

        pop     h
        ret

MINMAX                   ; the recursive scoring function
        mov     a, c     ; save depth
        sta     DEPTH
        mov     a, d
        sta     ALPHA
        mov     a, e
        sta     BETA

; debug
        call    INCMC
; enddebug

        lda     DEPTH           ; # of pieces played so far == 1 + depth
        cpi     4               ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      SKIPWIN

        call    WINNER         ; look for a winning position

        cpi     XPIECE
        jnz     MMNOTX
        mvi     a, WSCO        ; winning score
        ret

MMNOTX  cpi     OPIECE
        jnz     MMNOTO
        mvi     a, LSCO        ; losing score
        ret

MMNOTO  lda     DEPTH
        cpi     8
        jnz     SKIPWIN
        mvi     a, TSCO        ; tie score
        ret

SKIPWIN
        lda     DEPTH          ; min/max check
        mov     c, a
        mvi     a, 1
        ana     c
        jz      MMMIN        

        mvi     a, NSCO        ; maximizing odd depths
        sta     V
        mvi     a, XPIECE
        sta     PM
        jmp     MMFOR

MMMIN   mvi     a, XSCO
        sta     V
        mvi     a, OPIECE
        sta     PM

MMFOR   mvi     a, 0            ; I will go from 0..8
        sta     I

MMLOOP  mvi     b, 0            ; check if we can write to this board position
        mov     c, a
        lxi     h, BOARD
        dad     b
        mov     b, h
        mov     c, l
        ldax    b
        cpi     0               ; is the board space free?
        jnz     MMLEND

        lda     PM              ; store the current Piece Move in the free spot
        stax    b
        push    b               ; save the pointer to the board position for restoration later

        ; save state, recurse, and restore state

        lda     ALPHA
        mov     d, a
        lda     BETA
        mov     e, a
        push    d
        lda     I
        mov     b, a
        lda     PM
        mov     c, a
        push    b
        lda     V
        mov     b, a
        lda     DEPTH
        mov     c, a
        push    b
        inr     c
        
        ; D = alpha, E = beta, C = depth, A = return score

        call    MINMAX
        sta     SC        ; save the score

        pop     b
        mov     a, c
        sta     DEPTH
        mov     a, b
        sta     V
        pop     b
        mov     a, c
        sta     PM
        mov     a, b
        sta     I
        pop     d
        mov     a, d
        sta     ALPHA
        mov     a, e
        sta     BETA

        pop     b           ; restore the 0 in the board where the turn was placed
        mvi     a, 0
        stax    b

MMENDD
        lda     DEPTH
        mov     c, a
        mvi     a, 1
        ana     c
        jz      MMSMIN           ; min/max check

        lda     V                ; maximize case
        mov     b, a
        lda     SC
        cmp     b
        jm      MMNOMAX
        jz      MMNOMAX          ; no j <= 0 instruction on 8085
        sta     V                ; update V with the new best score
MMNOMAX
        lda     ALPHA
        mov     b, a
        lda     V
        cmp     b                ; V - ALPHA
        jm      MMNOALP
        sta     ALPHA            ; new alpha
MMNOALP
        lda     BETA
        mov     b, a
        lda     ALPHA
        cmp     b                ; Alpha - Beta
        jm      MMXEAR
        lda     V
        ret                      ; Alpha pruning
MMXEAR  lda     V
        cpi     WSCO             ; V - WSCO. If zero, can't do better.
        jnz     MMLEND
        ret
MMSMIN
        lda     V
        mov     b, a
        lda     SC
        cmp     b                ; SC - V
        jp      MMNOMIN
        sta     V
MMNOMIN
        lda     BETA
        mov     b, a
        lda     V
        cmp     b                ; V - Beta
        jp      MMNOBET
        sta     BETA             ; new beta
MMNOBET
        mov     b, a
        lda     ALPHA
        cmp     b                ; Alpha - Beta
        jm      MMNEAR
        lda     V
        ret                      ; Beta pruning
MMNEAR  lda     V
        cpi     LSCO             ; V - LSCO. If zero, can't do worse.
        jnz     MMLEND
        ret
MMLEND

        lda     I
        inr     a
        sta     I
        cpi     9                ; a - 9.  Want to loop for 0..8
        jm      MMLOOP

MMDONE
        lda     V
        ret

WINNER  ; returns winner (0, 1, 2) in register a
        ;  0 1 2
        ;  3 4 5
        ;  6 7 8
        lda     BOARD
L05005
        cpi     0
        jz      L05020

L05010
        lxi     h, BOARD + 1
        cmp     m
        jnz     L05015
        lxi     h, BOARD + 2
        cmp     m
        jnz     L05015
        ret

L05015
        lxi     h, BOARD + 3
        cmp     m
        jnz     L05020
        lxi     h, BOARD + 6
        cmp     m
        jnz     L05020
        ret

L05020        
        lda     BOARD + 3
        cpi     0
        jz      L05025
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05025
        lxi     h, BOARD + 5
        cmp     m
        jnz     L05025
        ret

L05025        
        lda     BOARD + 6
        cpi     0
        jz      L05030
        lxi     h, BOARD + 7
        cmp     m
        jnz     L05030
        lxi     h, BOARD + 8
        cmp     m
        jnz     L05030
        ret

L05030
        lda     BOARD + 1
        cpi     0
        jz      L05035
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05035
        lxi     h, BOARD + 7
        cmp     m
        jnz     L05035
        ret

L05035
        lda     BOARD + 2
        cpi     0
        jz      L05040
        lxi     h, BOARD + 5
        cmp     m
        jnz     L05040
        lxi     h, BOARD + 8
        cmp     m
        jnz     L05040
        ret

L05040
        lda     BOARD
        cpi     0
        jz      L05045
        lxi     h, BOARD + 4
        cmp     m
        jnz     L05045
        lxi     h, BOARD + 8
        cmp     m
        jnz     L05045
        ret

L05045
        lda     BOARD + 2
        cpi     0
        jz      WINONE
        lxi     h, BOARD + 4
        cmp     m
        jnz     WINONE
        lxi     h, BOARD + 6
        cmp     m
        jnz     WINONE
        ret

WINONE
        mvi     a, 0           ; no winning piece
        ret

DISPLY:                        ; display null-terminated string pointed to by hl
        push    h
        push    d
        push    b

        mov     b, h
        mov     c, l

DNEXT:
        ldax    b
        cpi     0
        jz      DDONE
        call    DISONE
        inx     b
        jmp     DNEXT

DDONE:
        pop     b
        pop     d
        pop     h
        ret

DIHEX:   ; Argument word is loaded into hl. Format word as Hex
        push    h
        push    d
        push    b

        mov     a, l
        ani     0fh
        cpi     10                  ; a - 10
        jp      HIHEX1
        adi     48
        jmp     NIB1
HIHEX1
        adi     87
NIB1
        sta     STRHEX + 3

        mov     a, l
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        cpi     10
        jp      HIHEX2
        adi     48
        jmp     NIB2
HIHEX2
        adi     87
NIB2
        sta     STRHEX + 2

        mov     a, h
        ani     0fh
        cpi     10
        jp      HIHEX3
        adi     48
        jmp     NIB3
HIHEX3
        adi     87
NIB3
        sta     STRHEX + 1

        mov     a, h
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        cpi     10
        jp      HIHEX4
        adi     48
        jmp     NIB4
HIHEX4
        adi     87
NIB4
        sta     STRHEX

        lxi     h, STRHEX
        call    DISPLY

        pop     b
        pop     d
        pop     h
        ret

        end

