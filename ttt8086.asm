        .model tiny
        .stack

; DOS constants

dos_write_char     equ   2h
dos_get_systemtime equ   1ah
dos_exit           equ   4ch

iterations  equ     10   ; # of times to run (max 32767)
max_score   equ     9    ; maximum score
min_score   equ     2    ; minimum score
win_score   equ     6    ; winning score
tie_score   equ     5    ; tie score
lose_score  equ     4    ; losing score
x_piece     equ     1    
o_piece     equ     2    
blank_piece equ     0

; these variables are all 1-byte, but 8086 requires push/pop be 2 bytes at a time
; local variables in minmax relative to bp/sp

value_offset   equ  0
i_offset       equ  2

; arguments to minmax relative to bp/sp
; space between locals and arguments:
;   2 or 4 bytes for return pc if minmax is NEAR or FAR (it's NEAR here)
;   2 bytes to save BP

alpha_offset   equ   8
beta_offset    equ  10

CODE SEGMENT PUBLIC 'CODE'
ORG 100h
startup PROC NEAR
        xor      ax, ax
        int      1ah
        mov      WORD PTR ds: [ starttime ], dx
        mov      WORD PTR ds: [ starttime + 2 ], cx

        lea      si, ds: [ offset board ]  ; global board pointer

again:
        xor      bx, bx     ; zero the global move count

        ; run for the 3 unique first moves

        mov      ax, 0
        call     runmm
        mov      ax, 1
        call     runmm
        mov      ax, 4
        call     runmm

        inc      WORD PTR ds: [ iters ]
        cmp      ds: [ iters ], iterations
        jne      again

        push     bx

        call     printelap
        mov      dx, offset secondsmsg
        call     printstring

        mov      dx, offset movesmsg
        call     printstring

        pop      ax
        call     printint
        call     printcrlf

        mov      dx, offset iterationsmsg
        call     printstring

        mov      ax, ds: [iters]
        call     printint
        call     printcrlf

        mov      al, 0
        mov      ah, dos_exit
        int      21h
startup ENDP

runmm PROC NEAR
        ; make the first move
        mov       di, ax
        push      di
        mov       BYTE PTR [ offset board + di ], x_piece

        ; alpha and beta passed on the stack
        ; current move in di
        ; current depth in cx
        ; global move count in bx
        ; global board pointer in si

        xor       cx, cx            ; depth in cx
        mov       ax, max_score     ; pushing constants didn't start until the 80186
        push      ax                ; beta
        mov       ax, min_score
        push      ax                ; alpha

        call      minmax_min
        add       sp, 4

        ; restore the board at the first move position

        pop       di
        mov       BYTE PTR ds: [ offset board + di ], blank_piece

        ret
runmm ENDP

minmax_max PROC NEAR
        push     bp
        sub      sp, 4              ; allocate space for local variables i and value
        mov      bp, sp             ; set bp to the stack location

        inc      bx                 ; increment global move count

        cmp      cx, 4
        jl       SHORT _max_no_winner_check

        shl      di, 1
        mov      ax, o_piece
        call     ds: WORD PTR [ offset winprocs + di ]

        cmp      al, o_piece
        mov      ax, lose_score
        je       SHORT _max_just_return_ax

  _max_no_winner_check:
        mov      WORD PTR [ bp + value_offset ], min_score
        mov      di, -1

  _max_loop:
        inc      di
        cmp      di, 9
        je       SHORT _max_load_value_return

        mov      WORD PTR [ bp + i_offset ], di
        cmp      BYTE PTR ds: [ offset board + di ], 0
        jne      SHORT _max_loop

        mov      BYTE PTR ds: [ offset board + di ], x_piece

        inc      cx
        push     [ bp + beta_offset ]
        push     [ bp + alpha_offset ]

        call     minmax_min
        add      sp, 4              ; cleanup stack for arguments
        dec      cx

        mov      di, [ bp + i_offset ]
        mov      BYTE PTR ds: [ offset board + di ], 0

        cmp      ax, win_score
        je       SHORT _max_just_return_ax

        cmp      ax, [ bp + value_offset ]
        jle      SHORT _max_ab_prune
        mov      [ bp + value_offset ], ax

  _max_ab_prune:
        mov      ax, [ bp + value_offset ]
        cmp      ax, [ bp + alpha_offset ]
        jle      SHORT _max_check_beta
        mov      [ bp + alpha_offset ], ax

  _max_check_beta:
        mov      ax, [ bp + alpha_offset ]
        cmp      ax, [ bp + beta_offset ]
        jl       SHORT _max_loop

  _max_load_value_return:
        mov      ax, [ bp + value_offset ]

  _max_just_return_ax:
        add      sp, 4              ; cleanup stack for locals
        pop      bp
        ret
minmax_max ENDP

minmax_min PROC NEAR
        push     bp
        sub      sp, 4              ; allocate space for local variables i and value
        mov      bp, sp             ; set bp to the stack location

        inc      bx                 ; increment global move count

        cmp      cx, 4
        jl       SHORT _min_no_winner_check

        shl      di, 1
        mov      ax, x_piece
        call     ds: WORD PTR [ offset winprocs + di ]

        cmp      al, x_piece
        mov      ax, win_score
        je       SHORT _min_just_return_ax

        cmp      cx, 8
        mov      ax, tie_score
        je       SHORT _min_just_return_ax

  _min_no_winner_check:
        mov      WORD PTR [ bp + value_offset ], max_score
        mov      di, -1

  _min_loop:
        inc      di
        cmp      di, 9
        je       SHORT _min_load_value_return

        mov      WORD PTR [ bp + i_offset ], di
        cmp      BYTE PTR ds: [ offset board + di ], 0
        jne      SHORT _min_loop

        mov      BYTE PTR ds: [ offset board + di ], o_piece

        inc      cx
        push     [ bp + beta_offset ]
        push     [ bp + alpha_offset ]

        call     minmax_max
        add      sp, 4              ; cleanup stack for arguments
        dec      cx

        mov      di, [ bp + i_offset ]
        mov      BYTE PTR ds: [ offset board + di ], 0

        cmp      ax, lose_score
        je       SHORT _min_just_return_ax

        cmp      ax, [ bp + value_offset ]
        jge      SHORT _min_ab_prune
        mov      [ bp + value_offset ], ax

  _min_ab_prune:
        mov      ax, [ bp + value_offset ]
        cmp      ax, [ bp + beta_offset ]
        jge      SHORT _min_check_alpha
        mov      [ bp + beta_offset ], ax

  _min_check_alpha:
        mov      ax, [ bp + beta_offset ]
        cmp      ax, [ bp + alpha_offset ]
        jg       SHORT _min_loop

  _min_load_value_return:
        mov      ax, [ bp + value_offset ]

  _min_just_return_ax:
        add      sp, 4              ; cleanup stack for locals
        pop      bp
        ret
minmax_min ENDP

; winner is no longer used since function pointers with the most recent move in ax are much faster

winner PROC NEAR
        xor      ax, ax
        mov      al, [ si ]
        cmp      al, 0
        je       _win_check_3

        cmp      al, [ si + 1 ]
        jne      _win_check_0_b
        cmp      al, [ si + 2 ]
        jne      _win_check_0_b
        ret

  _win_check_0_b:
        cmp      al, [ si + 3 ]
        jne      _win_check_3
        cmp      al, [ si + 6 ]
        jne      _win_check_3
        ret

  _win_check_3:
        mov      al, [ si + 3 ]
        cmp      al, 0
        je       _win_check_6

        cmp      al, [ si + 4 ]
        jne      _win_check_6
        cmp      al, [ si + 5 ]
        jne      _win_check_6
        ret

  _win_check_6:
        mov      al, [ si + 6 ]
        cmp      al, 0
        je       _win_check_1

        cmp      al, [ si + 7 ]
        jne      _win_check_1
        cmp      al, [ si + 8 ]
        jne      _win_check_1
        ret

  _win_check_1:
        mov      al, [ si + 1 ]
        cmp      al, 0
        je       _win_check_2

        cmp      al, [ si + 4 ]
        jne      _win_check_2
        cmp      al, [ si + 7 ]
        jne      _win_check_2
        ret
        
  _win_check_2:
        mov      al, [ si + 2 ]
        cmp      al, 0
        je       _win_check_4

        cmp      al, [ si + 5 ]
        jne      _win_check_4
        cmp      al, [ si + 8 ]
        jne      _win_check_4
        ret

  _win_check_4:
        mov     al, [ si + 4 ]
        cmp     al, 0
        je      _win_return

        cmp     al, [ si ]
        jne     _win_check_4_b
        cmp     al, [ si  + 8 ]
        jne     _win_check_4_b
        ret

  _win_check_4_b:
        cmp     al, [ si + 2 ]
        jne     _win_return_blank
        cmp     al, [ si + 6 ]
        je      _win_return

  _win_return_blank:
        xor     ax, ax
  _win_return:
        ret
winner ENDP

; print the integer in ax

printint PROC NEAR
        test     ah, 80h
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si

        jz       _prpositive
        neg      ax                 ; just one instruction for complement + 1
        push     ax
        mov      dx, '-'
        mov      ah, dos_write_char
        int      21h
        pop      ax
  _prpositive:
        xor      cx, cx
        xor      dx, dx
        cmp      ax, 0
        je       _przero
  _prlabel1:
        cmp      ax, 0
        je       _prprint1     
        mov      bx, 10       
        div      bx                 
        push     dx             
        inc      cx             
        xor      dx, dx
        jmp      _prlabel1
  _prprint1:
        cmp      cx, 0
        je       _prexit
        pop      dx
        add      dx, 48
        mov      ah, dos_write_char
        int      21h
        dec      cx
        jmp      _prprint1
  _przero:
        mov      dx, '0'
        mov      ah, dos_write_char
        int      21h
  _prexit:
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
printint ENDP

printcrlf PROC NEAR
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si
        mov      dx, offset crlfmsg
        call     printstring
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
printcrlf ENDP

printcommasp PROC NEAR
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si
        mov      dx, offset commaspmsg
        call     printstring
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
printcommasp ENDP

prperiod PROC NEAR
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si
        mov      dx, '.'
        mov      ah, dos_write_char
        int      21h
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
prperiod ENDP

printelap PROC NEAR
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si
        xor      ax, ax
        int      1ah
        mov      WORD PTR ds: [ scratchpad ], dx
        mov      WORD PTR ds: [ scratchpad + 2 ], cx
        mov      dl, 0
        mov      ax, WORD PTR ds: [ scratchpad ]
        mov      bx, WORD PTR ds: [ starttime ]
        sub      ax, bx
        mov      word ptr ds: [ result ], ax
        mov      ax, WORD PTR ds: [ scratchpad + 2 ]
        mov      bx, WORD PTR ds: [ starttime + 2 ]
        sbb      ax, bx
        mov      word ptr ds: [ result + 2 ], ax
        mov      dx, word ptr ds: [ result + 2 ]
        mov      ax, word ptr ds: [ result ]
        mov      bx, 10000
        mul      bx
        mov      bx, 18206
        div      bx
        xor      dx, dx
        mov      bx, 10
        div      bx
        push     dx
        call     printint
        call     prperiod
        pop      ax
        call     printint
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
printelap ENDP

printstring PROC NEAR
        push     ax
        push     bx
        push     cx
        push     dx
        push     di
        push     si

        mov      di, dx

  _psnext:
      
        mov      al, BYTE PTR ds: [ di ]
        cmp      al, 0
        je       _psdone
        mov      dx, ax
        mov      ah, dos_write_char
        int      21h

        inc      di
        jmp      _psnext

  _psdone:
        pop      si
        pop      di
        pop      dx
        pop      cx
        pop      bx
        pop      ax
        ret
printstring ENDP

align 2
proc0 PROC NEAR
    cmp     al, [si + 1]
    jne     SHORT proc0_next_win
    cmp     al, [si + 2]
    je      SHORT proc0_yes

  proc0_next_win:
    cmp     al, [si + 3]
    jne     SHORT proc0_next_win2
    cmp     al, [si + 6]
    je      SHORT proc0_yes

  proc0_next_win2:
    cmp     al, [si + 4]
    jne     SHORT proc0_no
    cmp     al, [si + 8]
    je      SHORT proc0_yes

  proc0_no:
    xor     ax, ax

  proc0_yes:
    ret
proc0 ENDP

align 2
proc1 PROC NEAR
    cmp     al, [si + 0]
    jne     SHORT proc1_next_win
    cmp     al, [si + 2]
    je      SHORT proc1_yes

  proc1_next_win:
    cmp     al, [si + 4]
    jne     SHORT proc1_no
    cmp     al, [si + 7]
    je      SHORT proc1_yes

  proc1_no:
    xor     ax, ax
    ret

  proc1_yes:
    ret
proc1 ENDP

align 2
proc2 PROC NEAR
    cmp     al, [si + 0]
    jne     SHORT proc2_next_win
    cmp     al, [si + 1]
    je      SHORT proc2_yes

  proc2_next_win:
    cmp     al, [si + 5]
    jne     SHORT proc2_next_win2
    cmp     al, [si + 8]
    je      SHORT proc2_yes

  proc2_next_win2:
    cmp     al, [si + 4]
    jne     SHORT proc2_no
    cmp     al, [si + 6]
    je      SHORT proc2_yes

  proc2_no:
    xor      ax, ax
    ret

  proc2_yes:
    ret
proc2 ENDP

align 2
proc3 PROC NEAR
    cmp     al, [si + 0]
    jne     SHORT proc3_next_win
    cmp     al, [si + 6]
    je      SHORT proc3_yes

  proc3_next_win:
    cmp     al, [si + 4]
    jne     SHORT proc3_no
    cmp     al, [si + 5]
    je      SHORT proc3_yes

  proc3_no:
    xor     ax, ax
    ret

  proc3_yes:
    ret
proc3 ENDP

align 2
proc4 PROC NEAR
    cmp     al, [si + 0]
    jne     SHORT proc4_next_win
    cmp     al, [si + 8]
    je      SHORT proc4_yes

  proc4_next_win:
    cmp     al, [si + 2]
    jne     SHORT proc4_next_win2
    cmp     al, [si + 6]
    je      SHORT proc4_yes

  proc4_next_win2:
    cmp     al, [si + 1]
    jne     SHORT proc4_next_win3
    cmp     al, [si + 7]
    je      SHORT proc4_yes

  proc4_next_win3:
    cmp     al, [si + 3]
    jne     SHORT proc4_no
    cmp     al, [si + 5]
    je      SHORT proc4_yes

  proc4_no:
    xor     ax, ax
    ret

  proc4_yes:
    ret
proc4 ENDP

align 2
proc5 PROC NEAR
    cmp     al, [si + 3]
    jne     SHORT proc5_next_win
    cmp     al, [si + 4]
    je      SHORT proc5_yes

  proc5_next_win:
    cmp     al, [si + 2]
    jne     SHORT proc5_no
    cmp     al, [si + 8]
    je      SHORT proc5_yes

  proc5_no:
    xor      ax, ax
    ret

  proc5_yes:
    ret
proc5 ENDP

align 2
proc6 PROC NEAR
    cmp     al, [si + 4]
    jne     SHORT proc6_next_win
    cmp     al, [si + 2]
    je      SHORT proc6_yes

  proc6_next_win:
    cmp     al, [si + 0]
    jne     SHORT proc6_next_win2
    cmp     al, [si + 3]
    je      SHORT proc6_yes

  proc6_next_win2:
    cmp     al, [si + 7]
    jne     SHORT proc6_no
    cmp     al, [si + 8]
    je      SHORT proc6_yes

  proc6_no:
    xor      ax, ax
    ret

  proc6_yes:
    ret
proc6 ENDP

align 2
proc7 PROC NEAR
    cmp     al, [si + 1]
    jne     SHORT proc7_next_win
    cmp     al, [si + 4]
    je      SHORT proc7_yes

  proc7_next_win:
    cmp     al, [si + 6]
    jne     SHORT proc7_no
    cmp     al, [si + 8]
    je      SHORT proc7_yes

  proc7_no:
    xor     ax, ax
    ret

  proc7_yes:
    ret
proc7 ENDP

align 2
proc8 PROC NEAR
    cmp     al, [si + 0]
    jne     SHORT proc8_next_win
    cmp     al, [si + 4]
    je      SHORT proc8_yes

  proc8_next_win:
    cmp     al, [si + 2]
    jne     SHORT proc8_next_win2
    cmp     al, [si + 5]
    je      SHORT proc8_yes

  proc8_next_win2:
    cmp     al, [si + 6]
    jne     SHORT proc8_no
    cmp     al, [si + 7]
    je      SHORT proc8_yes

  proc8_no:
    xor      ax, ax
    ret

  proc8_yes:
    ret
proc8 ENDP

crlfmsg       db      13,10,0
secondsmsg    db      ' seconds',13,10,0
iterationsmsg db      'iterations: ',0
movesmsg      db      'moves: ',0
commaspmsg    db      ', ',0
board         db      0,0,0,0,0,0,0,0,0

align 2
iters      dw      0        ; iterations of running the app

align 4
scratchpad dd      0
starttime  dd      0
result     dd      0

align 2
winprocs   dw      proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

CODE ENDS

END
