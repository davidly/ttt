DISPLY  equ     05a58h  ; display string pointed to by hl
DISONE  equ     04b44h  ; display character in A
SECS    equ     0f933h  ; memory location for seconds (doesn't seem to work)
CHGET   equ     012cbh  ; get a character
XSCO    equ     9       ; maximum score
NSCO    equ     2       ; minimum score
WSCO    equ     6       ; winning score
TSCO    equ     5       ; tie score
LSCO    equ     4       ; losing score
XPIECE  equ     1       ; X move piece
OPIECE  equ     2       ; Y move piece

        aseg
        org     0c738h  ; 51000 decimal

; debug
;        call    WINNER
;        lxi     hl,CRLF
;        call    DISPLY
;        lxi     hl, STRWIN
;        call    DISPLY
;        lda     WI
;        mov     b,a
;        call    DISDIG
; enddebug

        push    bc
        push    de
        push    hl

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
;        sta     WI
;        sta     V
;        sta     I
;        sta     SC
;        sta     PM
;        sta     DEPTH
;        sta     ALPHA
;        sta     BETA

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
                                 
        lxi     hl,CRLF          ; Show the move count; the # of moves generated and considered
        call    DISPLY
        lxi     hl, STREXA
        call    DISPLY
        lhld    MOVES
        call    DIHEX
        lxi     hl,CRLF
        call    DISPLY

        pop     hl
        pop     de
        pop     bc

        ret

RUNMM                ; Run the MINMAX function for a given board
                     ; D = alpha, E = beta, C = depth
        mvi     d, NSCO
        mvi     e, XSCO
        mvi     c, 0
        
        call    MINMAX
        mov     b,a
        push    bc

        lxi     hl, STRWIN
        call    DISPLY

        pop     bc
        call    DISDIG

        ret

;PBOARD                    ; print the board
;        push    bc
;        push    de
;        push    hl
;
;        lxi     hl,CRLF
;        call    DISPLY
;
;        lda     BOARD
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 1
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 2
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 3
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 4
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 5
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 6
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 7
;        mov     b,a
;        call    DISDIG
;        lda     BOARD + 8
;        mov     b,a
;        call    DISDIG
;        lxi     hl,CRLF
;        call    DISPLY
;
;        pop     hl
;        pop     de
;        pop     bc
;        ret

INCMC                    ; increment move count
        push    hl

        lhld    MOVES
        inx     hl
        shld    MOVES

        pop     hl
        ret

;DBGMM
;        push    bc
;        push    de
;        push    hl
;        mov     b, a
;        push    bc
;
;        mvi     a, 'Z'
;        call    DISONE
;
;        pop     bc
;        mov     a, b
;        pop     hl
;        pop     de
;        pop     bc
;
;        ret

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

; debug
;        push    bc
;        mvi     a, 'D'
;        call    DISONE
;        mov     b, c
;        call    DISDIG
;        pop     bc
;        call    PBOARD
;        call    CHGET
; enddebug

        lda     DEPTH           ; # of pieces played so far == 1 + depth
        cpi     4               ; DEPTH - 4  (if 4 or fewer pieces played, no possible winner)
        jm      SKIPWIN

; debug
;        push    bc
;        mvi     a, 'd'
;        call    DISONE
;        lda     DEPTH
;        mov     b, a
;        call    DISDIG
;        mvi     a, ' '
;        call    DISONE
;        call    PBOARD
;        pop     bc
; enddebug

        call    WINNER         ; look for a winning position

; debug
;        mvi     a, 'W'
;        call    DISONE
;        call    CHGET
;        lda     WI
;        mov     b,a
;        call    DISDIG
; enddebug

        lda     WI

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
        lxi     hl, BOARD
        dad     bc
        mov     b, h
        mov     c, l
        ldax    bc
        cpi     0               ; is the board space free?
        jnz     MMLEND

        lda     PM              ; store the current Piece Move in the free spot
        stax    bc
        push    bc              ; save the pointer to the board position for restoration later

; debug
;        push    bc
;        mvi     a, 'd'
;        call    DISONE
;        lda     DEPTH
;        mov     b, a
;        call    DISDIG
;        pop     bc
;; end debug

        ; save state, recurse, and restore state

        lda     ALPHA
        mov     d, a
        lda     BETA
        mov     e, a
        push    de
        lda     I
        mov     b, a
        lda     PM
        mov     c, a
        push    bc
        lda     V
        mov     b, a
        lda     DEPTH
        mov     c, a
        push    bc
        inr     c
        
        ; D = alpha, E = beta, C = depth, A = return score

        call    MINMAX
        sta     SC        ; save the score

        pop     bc
        mov     a, c
        sta     DEPTH
        mov     a, b
        sta     V
        pop     bc
        mov     a, c
        sta     PM
        mov     a, b
        sta     I
        pop     de
        mov     a, d
        sta     ALPHA
        mov     a, e
        sta     BETA

        pop     bc           ; restore the 0 in the board where the turn was placed
        mvi     a, 0
        stax    bc

; debug
;        lda     DEPTH
;        cpi     7
;        jnz     MMENDD
;        push    bc
;        mvi     a, 'D'
;        call    DISONE
;        lda     DEPTH
;        mov     b, a
;        call    DISDIG
;        pop     bc
; end debug


; debug
;        push    bc
;        mvi     a, 'V'
;        call    DISONE
;        lda     V
;        mov     b, a
;        call    DISDIG
;        mvi     a, 'S'
;        call    DISONE
;        lda     SC
;        mov     b,a
;        call    DISDIG
;        pop     bc
; end debug

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

; debug
;        lda     DEPTH
;        cpi     0           ; a - X
;        jnz     SKIPHD
;
;        lxi     hl,CRLF
;        call    DISPLY
;        lhld    MOVES
;        call    DIHEX
;SKIPHD
; enddebug

        lda     I
        inr     a
        sta     I
        cpi     9                ; a - 9.  Want to loop for 0..8
        jm      MMLOOP

MMDONE
        lda     V
        ret

DISDIG  ; Argument # 0-9 is in register B
        mvi     a, 48
        add     b
        call    DISONE
        ret

DIHEX   ; Argument word is loaded into hl. Format word as Hex
        push    hl
        push    de
        push    bc

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

        lxi     hl, STRHEX
        call    DISPLY

        pop     bc
        pop     de
        pop     hl
        ret

WINNER  ; returns winner (0, 1, 2) in W
        ;  0 1 2
        ;  3 4 5
        ;  6 7 8
        lda     BOARD
        sta     WI
L05005
        cpi     0
        jz      L05020

L05010
        lda     WI
        lxi     hl, BOARD + 1
        cmp     m
        jnz     L05015
        lxi     hl, BOARD + 2
        cmp     m
        jnz     L05015
        ret

L05015
        lxi     hl, BOARD + 3
        cmp     m
        jnz     L05020
        lxi     hl, BOARD + 6
        cmp     m
        jnz     L05020
        ret

L05020        
        lda     BOARD + 3
        sta     WI
        cpi     0
        jz      L05025
        lxi     hl, BOARD + 4
        cmp     m
        jnz     L05025
        lxi     hl, BOARD + 5
        cmp     m
        jnz     L05025
        ret

L05025        
        lda     BOARD + 6
        sta     WI
        cpi     0
        jz      L05030
        lxi     hl, BOARD + 7
        cmp     m
        jnz     L05030
        lxi     hl, BOARD + 8
        cmp     m
        jnz     L05030
        ret

L05030
        lda     BOARD + 1
        sta     WI
        cpi     0
        jz      L05035
        lxi     hl, BOARD + 4
        cmp     m
        jnz     L05035
        lxi     hl, BOARD + 7
        cmp     m
        jnz     L05035
        ret

L05035
        lda     BOARD + 2
        sta     WI
        cpi     0
        jz      L05040
        lxi     hl, BOARD + 5
        cmp     m
        jnz     L05040
        lxi     hl, BOARD + 8
        cmp     m
        jnz     L05040
        ret

L05040
        lda     BOARD
        sta     WI
        cpi     0
        jz      L05045
        lxi     hl, BOARD + 4
        cmp     m
        jnz     L05045
        lxi     hl, BOARD + 8
        cmp     m
        jnz     L05045
        ret

L05045
        lda     BOARD + 2
        sta     WI
        cpi     0
        jz      WINONE
        lxi     hl, BOARD + 4
        cmp     m
        jnz     WINONE
        lxi     hl, BOARD + 6
        cmp     m
        jnz     WINONE
        ret

WINONE
        mvi     a, 0           ; no winning piece
        sta     WI
        ret
        
        
STRWIN  db      "Winner: ",00
STRSEC  db      "Seconds: ",00
STRSCO  db      "Score: ",00
STREXA  db      "Moves Examined: ",00
STRHEX  db      "0000",00
CRLF    db      10,13,0
BOARD   db      0,0,0,0,0,0,0,0,0
WI      db      0      ; winner return value
V       db      0      ; value in minmax
I       db      0      ; Index in 0..8 loop in MinMax
SC      db      0      ; score in MinMax
PM      db      0      ; piece move -- current move in MinMax
DEPTH   db      0      ; current depth of recursion
ALPHA   db      0      ; Alpha in a/b pruning
BETA    db      0      ; Beta in a/b pruning
MOVES   db      0, 0

        end
