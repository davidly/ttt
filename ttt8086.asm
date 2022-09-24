        .model tiny
        .stack

; DOS constants

dos_write_string   equ   9h
dos_write_char     equ   2h
dos_get_systemtime equ   1ah
dos_exit           equ   4ch

; these variables are all 1-byte, but 8086 requires push/pop be 2 bytes at a time

iterations  equ   100   ; # of times to run (max 32767)
max_score   equ     9   ; maximum score
min_score   equ     2   ; minimum score
win_score   equ     6   ; winning score
tie_score   equ     5   ; tie score
lose_score  equ     4   ; losing score
x_piece     equ     1 
o_piece     equ     2 
blank_piece equ     0

; local variables in minmax relative to bp/sp

pm_offset      equ  6
i_offset       equ  4
score_offset   equ  2
value_offset   equ  0

; arguments to minmax relate to bp/sp

alpha_offset   equ  12
beta_offset    equ  14
depth_offset   equ  16
move_offset    equ  18

CODE SEGMENT PUBLIC 'CODE'
ORG 100h
startup PROC FAR
again:
        mov      [moves], 0

        mov      ax, 0
        call     runmm

        mov      ax, 1
        call     runmm

        mov      ax, 4
        call     runmm

        inc      WORD PTR [ iters ]
        cmp      [ iters ], iterations
        jne      again

        mov      ah, dos_write_string
        mov      dx, offset movesmsg
        int      21h

        mov      ax, [MOVES]
        call     printint
        call     printcrlf

        mov      al, 0
        mov      ah, dos_exit
        int      21h
startup ENDP

runmm PROC FAR
        mov       di, ax
        push      di
        lea       si, [ offset board + di ]
        mov       BYTE PTR [si], x_piece

        push      di                ; move location
        xor       ax, ax
        push      ax                ; depth
        mov       ax, max_score
        push      ax                ; beta
        mov       ax, min_score
        push      ax                ; alpha

        call      minmax

        pop       ax
        pop       ax
        pop       ax
        pop       ax

        pop       di
        lea       si, [ offset board + di ]
        mov       BYTE PTR [si], blank_piece

        ret
runmm ENDP

minmax PROC FAR
        xor      ax, ax
        push     ax                 ; allocate space for PlayerMove
        push     ax                 ; allocate space for I
        push     ax                 ; allocate space for Score
        push     ax                 ; allocate space for value
        mov      bp, sp             ; set bp to the stack location

        inc      WORD PTR [ moves ]

        mov      ax, [ bp + depth_offset ]
        cmp      ax, 4
        jl       _no_winner_check

        call     winner

        cmp      ax, blank_piece
        je       _no_winner

        cmp      ax, x_piece
        jne      _o_winner
        mov      ax, win_score
        jmp      _just_return_ax

  _o_winner:
        mov      ax, lose_score
        jmp      _just_return_ax

  _no_winner:
        mov      ax, [ bp + depth_offset ]
        cmp      ax, 8
        jne      _no_winner_check
        mov      ax, tie_score
        jmp      _just_return_ax

  _no_winner_check:
        mov      ax, [ bp + depth_offset ]
        and      ax, 1
        je       _minimize_setup

        mov      ax, min_score
        mov      [ bp + value_offset ], ax
        mov      ax, x_piece
        mov      [ bp + pm_offset ], ax
        jmp      _loop

  _minimize_setup:
        mov      ax, max_score
        mov      [ bp + value_offset ], ax
        mov      ax, o_piece
        mov      [ bp + pm_offset ], ax

  _loop:
        mov      ax, [ bp + i_offset ]
        cmp      ax, 9
        je       _load_value_return

        mov      si, ax
        mov      al, BYTE PTR [ offset board + si ]
        cmp      al, 0
        jne      _next_i

        mov      ax, [ bp + pm_offset ]
        mov      BYTE PTR [ offset board + si ], al

        push     si
        mov      ax, [ bp + depth_offset ]
        inc      ax
        push     ax
        mov      ax, [ bp + beta_offset ]
        push     ax
        mov      ax, [ bp + alpha_offset ]
        push     ax

        call     minmax

        pop      bx
        pop      bx
        pop      bx
        pop      bx

        mov      bp, sp
        mov      [ bp + score_offset ], ax
        mov      si, [ bp + i_offset ]
        xor      ax, ax
        mov      BYTE PTR [ offset board + si ], al

        mov      ax, [ bp + depth_offset ]
        and      ax, 1
        je       _minimize_score

  _maximize_score:
        mov      ax, [ bp + score_offset ]
        cmp      ax, win_score
        je       _just_return_ax

        cmp      ax, [ bp + value_offset ]
        jle      _max_ab_prune
        mov      [ bp + value_offset ], ax

  _max_ab_prune:
        mov      ax, [ bp + value_offset ]
        cmp      ax, [ bp + alpha_offset ]
        jle      _max_check_beta
        mov      [ bp + alpha_offset ], ax

  _max_check_beta:
        mov      ax, [ bp + alpha_offset ]
        cmp      ax, [ bp + beta_offset ]
        jge      _load_value_return
        jmp      _next_i

  _minimize_score:
        mov      ax, [ bp + score_offset ]
        cmp      ax, lose_score
        je      _just_return_ax

        cmp      ax, [ bp + value_offset ]
        jge      _min_ab_prune
        mov      [ bp + value_offset ], ax

  _min_ab_prune:
        mov      ax, [ bp + value_offset ]
        cmp      ax, [ bp + beta_offset ]
        jge      _min_check_alpha
        mov      [ bp + beta_offset ], ax

  _min_check_alpha:
        mov      ax, [ bp + beta_offset ]
        cmp      ax, [ bp + alpha_offset ]
        jle      _load_value_return

  _next_i:
        inc      WORD PTR [ bp + i_offset ]
        jmp      _loop

  _load_value_return:
        mov      ax, [ bp + value_offset ]
  _just_return_ax:
        pop      bx
        pop      bx
        pop      bx
        pop      bx
        ret
minmax ENDP

winner PROC FAR
        xor      ax, ax
        lea      si, [offset board]
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

printint PROC FAR
        xor cx, cx
        xor dx, dx
        cmp ax, 0
        je przero
  prlabel1:
        cmp ax, 0
        je prprint1     
        mov bx, 10       
        div bx                 
        push dx             
        inc cx             
        xor dx, dx
        jmp prlabel1
  prprint1:
        cmp cx, 0
        je prexit
        pop dx
        add dx, 48
        mov ah, dos_write_char
        int 21h
        dec cx
        jmp prprint1
  przero:
        mov dx, '0'
        mov ah, dos_write_char
        int 21h
  prexit:
        ret
printint ENDP

printcrlf PROC FAR
        mov      ah, dos_write_string
        mov      dx, offset crlfmsg
        int      21h
        ret
printcrlf ENDP

printcommasp PROC FAR
        mov      ah, dos_write_string
        mov      dx, offset commaspmsg
        int      21h
        ret
printcommasp ENDP

crlfmsg    db      13,10,'$'
STRWIN     db      'winner ','$'
timemsg    db      'seconds: ','$'
movesmsg   db      'moves: ','$'
commaspmsg db      ', ','$'
board      db      0,0,0,0,0,0,0,0,0
moves      dw      0        ; Count of moves examined 
iters      dw      0        ; iterations of running the app

CODE ENDS

END
