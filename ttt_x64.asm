;
; Prove that you can't win at tic-tac-toe
; The g++ compiler generates better code in that the loop is unrolled and the minimize/maximize codepaths
; in the loop are separated. It's almost (9 * 2) = 18x as much code, but it's 25% faster.
;

extern ExitProcess: PROC
extern printf: PROC
extern puts: PROC
extern mainCRTStartup: PROC

; these short/terrible names are to support portability of names to 8085

XSCO    equ     9       ; maximum score
NSCO    equ     2       ; minimum score
WSCO    equ     6       ; winning score
TSCO    equ     5       ; tie score
LSCO    equ     4       ; losing score
XPIECE  equ     1       ; X move piece
OPIECE  equ     2       ; Y move piece

; local variable offsets [rbp - X] where X = 1 to N where N is the number of QWORDS beyond 4 reserved at entry
; These are for the function minmax()
V_OFFSET      equ 8 * 1            ; the value of a board position
I_OFFSET      equ 8 * 2            ; i in the for loop 0..8
PM_OFFSET     equ 8 * 3            ; player move X or O

; spill offsets -- [rbp + X] where X = 2..5  Spill referrs to saving parameters in registers to memory when needed
; these registers can be spilled: rcx, rdx, r8, r9
; These are for the function minmax()
A_S_OFFSET      equ 8 * 2        ; alpha
B_S_OFFSET      equ 8 * 3        ; beta
DEPTH_S_OFFSET  equ 8 * 4        ; depth in the recursion

.data
    BOARD    db      0,0,0,0,0,0,0,0,0
    caption  db      'Hello world!', 0
    fmtStr   db      'Format string int %I64d %I64d %I64d %I64d %I64d %s', 0
    pieceS   db      '%d', 0
    intS     db      '%d ', 0
    STRWIN   db      'winner: %d', 10, 13, 0
    moveStr  db      'moves: %d', 10, 13, 0
    dbgcw    db      'calling winner', 10, 13, 0
    CRLF     db      10, 13, 0
    WINPROCS dq      proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

.code
main PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 3

;    lea     rcx, [fmtStr]
;    mov     rdx, 17
;    mov     r8, 18
;    mov     r9, 19
;    mov     rbx, 20
;    mov     [rsp + 8 * 4 ], rbx
;    mov     rbx, 21
;    mov     [rsp + 8 * 5 ], rbx
;    lea     rbx, [caption]
;    mov     [rsp + 8 * 6 ], rbx
;    call    printf

    xor     r13, r13           ; count of moves examined (calls to minmax()). Global for whole app

;     mov     r15, 1
    mov     r15, 10000

  main_loopagain:
    lea     rcx, [BOARD]
    mov     al, XPIECE
    mov     [rcx], al
    mov     rcx, 0             ; piece placed at position 0
    call    minmaxdriver

    lea     rcx, [BOARD]
    mov     al, 0
    mov     [rcx], al
    lea     rcx, [BOARD + 1]
    mov     al, XPIECE
    mov     [rcx], al
    mov     rcx, 1             ; piece placed at position 1
    call    minmaxdriver

    lea     rcx, [BOARD + 1]
    mov     al, 0
    mov     [rcx], al
    lea     rcx, [BOARD + 4]
    mov     al, XPIECE
    mov     [rcx], al
    mov     rcx, 4             ; piece placed at position 4
    call    minmaxdriver

    lea     rcx, [BOARD + 4]
    mov     al, 0
    mov     [rcx], al
    
    dec     r15
    cmp     r15, 0
    jne     main_loopagain

; debugging winner
;    call    printboard
;    call    winner
;    mov     rdx, rax     ; return value
;    lea     rcx, STRWIN
;    call    printf

    mov      rdx, r13
    lea      rcx, moveStr
    call     printf

    xor     rax, rax

    ; these two instructions are identical to leave
    mov     rsp, rbp
    pop     rbp
    ;    leave

    ret
main ENDP

minmaxdriver PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

;    call    printboard
;    call    printCRLF

    mov     r9, rcx       ; position of last board update
    mov     rcx, NSCO     ; alpha
    mov     rdx, XSCO     ; beta
    xor     r8, r8        ; depth

    call    minmax

    mov     rdx, rax     ; return value
    lea     rcx, STRWIN
;    call    printf

    leave
    ret
minmaxdriver ENDP

printCRLF PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    lea     rcx, CRLF
    call    printf

    leave
    ret
printCRLF ENDP

printint PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    mov     rdx, rcx
    lea     rcx, [intS]

    call    printf

    leave
    ret
printint ENDP

printboard PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    xor     rax, rax
    xor     rbx, rbx

  pb_loop:
    lea     rcx, [BOARD]
    add     rcx, rbx
    mov     al, [rcx]

    lea     rcx, [pieceS]
    mov     rdx, rax
    call    printf

    inc     rbx
    cmp     rbx, 9
    jnz     pb_loop

    leave
    ret
printboard ENDP

minmax PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 80h   ; 128 decimal

    ; rcx = alpha, rdx = beta, r8 = depth. Store in spill locations reserved by parent stack
    ; r9 = position of last piece added 0..8. Keep in the register because it's used right away
    ; r10: unused
    ; r11: unused
    ; r12: i in the for loop
    ; r13: global minmax call count
    ; r14: V
    ; r15: unused

    inc     r13                             ; r13 is a global variable with the # of calls to minmax

    ; NOTE: r8, rcx, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     SHORT skip_winner

    ; winner_proc is inlined here
    mov     rax, 0                          ; the win procs expect rax and rbx to be 0 on entry 
    mov     rbx, 0
    lea     rsi, [WINPROCS]
    call    QWORD PTR[ rsi + r9 * 8 ]       ; winprocs is faster than winner_all and winner_registers
    mov     rbx, rax                        ; move to rbx because rax may get trashed by performance side-effects below

    cmp     bl, XPIECE                      ; did X win? 
    mov     rax, WSCO                       ; wasted mov, but it often saves a jump
    je      minmax_done

    cmp     bl, OPIECE                      ; did O win?
    mov     rax, LSCO                       ; wasted mov, but it often saves a jump
    je      minmax_done

    cmp     r8, 8                           ; recursion can only go 8 deep before the board is full
    mov     rax, TSCO                       ; wasted mov, but it often saves a jump
    je      minmax_done

  skip_winner:
    mov     [rbp + DEPTH_S_OFFSET ], r8     ; depth
    mov     [rbp + A_S_OFFSET ], rcx        ; alpha
    mov     [rbp + B_S_OFFSET ], rdx        ; beta

    test    r8d, 1                          ; odd depth means we're maximizing for X. 
    jz      SHORT minmax_minimize

    mov     r14, NSCO                       ; minimum possible score
    mov     rbx, XPIECE                     ; X will move
    mov     [rbp - PM_OFFSET], rbx          ; PM -- player move
    jmp     SHORT minmax_for

  minmax_minimize:
    mov     r14, XSCO                       ; maximum possible score
    mov     rbx, OPIECE                     ; O will move
    mov     [rbp - PM_OFFSET], rbx          ; PM -- player move

  minmax_for:
    mov     r12, 0                          ; r12 is I in the for loop 0..8

  minmax_loop:
    lea     rcx, [BOARD]                    ; Check if the board position is unused
    add     rcx, r12
    cmp     BYTE PTR [rcx], 0
    jne     minmax_loopend                  ; move to the next spot on the board

    mov     al, [rbp - PM_OFFSET]           ; load player move (X or O)
    mov     BYTE PTR [rcx], al              ; make the move

    ; prepare arguments for recursing
    ; read from stack spill locations, not local variable locations

    mov     rcx, [rbp + A_S_OFFSET]         ; alpha
    mov     rdx, [rbp + B_S_OFFSET]         ; beta
    inc     r8                              ; next depth 1..8
    mov     r9, r12                         ; position just claimed 0..8
    mov     [rbp - I_OFFSET], r12           ; save i -- the for loop variable
    mov     [rbp - V_OFFSET], r14           ; save V -- value of the current board position

    call    minmax                          ; score is in rax on return

    mov     r8, [rbp + DEPTH_S_OFFSET]      ; restore depth into r8
    mov     r12, [rbp - I_OFFSET]           ; restore i
    lea     rcx, [BOARD]                    ; Restore the move on the board to 0 from X or O
    mov     BYTE PTR [rcx + r12], 0

    test    r8, 1                           ; test if the depth is odd, which means maximize
    jz      SHORT minmax_minscore

    ; Maximize the score
    cmp     rax, WSCO
    je      SHORT minmax_done               ; can't do better than winning score when maximizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with V
    cmovg   r14, rax                        ; keep latest V in r14

    mov     rax, [rbp + A_S_OFFSET]         ; load alpha
    cmp     rax, r14                        ; compare alpha with V
    cmovl   rax, r14                        ; only update alpha if alpha is less than V

    cmp     rax, QWORD PTR [rbp + B_S_OFFSET] ; compare alpha (rax) with beta (in memory)
    jge     SHORT minmax_loadv_done         ; alpha pruning

    mov     [rbp + A_S_OFFSET], rax         ; update alpha with V or the same alpha value (to avoid a jump)
    jmp     SHORT minmax_loopend

  minmax_minscore: ; Minimize the score
    cmp     rax, LSCO
    je      SHORT minmax_done               ; can't do better than losing score when minimizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with v
    cmovl   r14, rax                        ; keep latest V in r14

    mov     rax, [rbp + B_S_OFFSET]         ; load beta
    cmp     rax, r14                        ; compare beta with V
    cmovg   rax, r14                        ; if V is less than Beta, update Beta

    cmp     rax, QWORD PTR [rbp + A_S_OFFSET ] ; compare beta (rax) with alpha (in memory)
    jle     SHORT minmax_loadv_done         ; beta pruning

    mov     [rbp + B_S_OFFSET], rax         ; update beta with a new value or the same value (to avoid a jump)

  minmax_loopend:                           ; bottom of the loop
    inc     r12
    cmp     r12, 9
    jl      minmax_loop

  minmax_loadv_done:
    mov     rax, r14                        ; load V then return

  minmax_done:
    leave
    ret
minmax ENDP

proc0 PROC
    mov     bl, [BOARD]
    cmp     bl, [BOARD + 1]
    jne     SHORT proc0_next_win
    cmp     bl, [BOARD + 2]
    je      SHORT proc0_yes

  proc0_next_win:
    cmp     bl, [BOARD + 3]
    jne     SHORT proc0_next_win2
    cmp     bl, [BOARD + 6]
    je      SHORT proc0_yes

  proc0_next_win2:
    cmp     bl, [BOARD + 4]
    jne     SHORT proc0_no
    cmp     bl, [BOARD + 8]
    je      SHORT proc0_yes
  proc0_no:
    ret

  proc0_yes:
    mov     rax, rbx
    ret
proc0 ENDP

proc1 PROC
    mov     bl, [BOARD + 1]
    cmp     bl, [BOARD + 0]
    jne     SHORT proc1_next_win
    cmp     bl, [BOARD + 2]
    je      SHORT proc1_yes

  proc1_next_win:
    cmp     bl, [BOARD + 4]
    jne     SHORT proc1_no
    cmp     bl, [BOARD + 7]
    je      SHORT proc1_yes
  proc1_no:
    ret

  proc1_yes:
    mov     rax, rbx
    ret
proc1 ENDP

proc2 PROC
    mov     bl, [BOARD + 2]
    cmp     bl, [BOARD + 0]
    jne     SHORT proc2_next_win
    cmp     bl, [BOARD + 1]
    je      SHORT proc2_yes

  proc2_next_win:
    cmp     bl, [BOARD + 5]
    jne     SHORT proc2_next_win2
    cmp     bl, [BOARD + 8]
    je      SHORT proc2_yes

  proc2_next_win2:
    cmp     bl, [BOARD + 4]
    jne     SHORT proc2_no
    cmp     bl, [BOARD + 6]
    je      SHORT proc2_yes
  proc2_no:
    ret

  proc2_yes:
    mov     rax, rbx
    ret
proc2 ENDP

proc3 PROC
    mov     bl, [BOARD + 3]
    cmp     bl, [BOARD + 4]
    jne     SHORT proc3_next_win
    cmp     bl, [BOARD + 5]
    je      SHORT proc3_yes

  proc3_next_win:
    cmp     bl, [BOARD + 0]
    jne     SHORT proc3_no
    cmp     bl, [BOARD + 6]
    je      SHORT proc3_yes
  proc3_no:
    ret

  proc3_yes:
    mov     rax, rbx
    ret
proc3 ENDP

proc4 PROC
    mov     bl, [BOARD + 4]
    cmp     bl, [BOARD + 0]
    jne     SHORT proc4_next_win
    cmp     bl, [BOARD + 8]
    je      SHORT proc4_yes

  proc4_next_win:
    cmp     bl, [BOARD + 2]
    jne     SHORT proc4_next_win2
    cmp     bl, [BOARD + 6]
    je      SHORT proc4_yes

  proc4_next_win2:
    cmp     bl, [BOARD + 1]
    jne     SHORT proc4_next_win3
    cmp     bl, [BOARD + 7]
    je      SHORT proc4_yes

  proc4_next_win3:
    cmp     bl, [BOARD + 3]
    jne     SHORT proc4_no
    cmp     bl, [BOARD + 5]
    je      SHORT proc4_yes
  proc4_no:
    ret

  proc4_yes:
    mov     rax, rbx
    ret
proc4 ENDP

proc5 PROC
    mov     bl, [BOARD + 5]
    cmp     bl, [BOARD + 3]
    jne     SHORT proc5_next_win
    cmp     bl, [BOARD + 4]
    je      SHORT proc5_yes

  proc5_next_win:
    cmp     bl, [BOARD + 2]
    jne     SHORT proc5_no
    cmp     bl, [BOARD + 8]
    je      SHORT proc5_yes
  proc5_no:
    ret

  proc5_yes:
    mov     rax, rbx
    ret
proc5 ENDP

proc6 PROC
    mov     bl, [BOARD + 6]
    cmp     bl, [BOARD + 4]
    jne     SHORT proc6_next_win
    cmp     bl, [BOARD + 2]
    je      SHORT proc6_yes

  proc6_next_win:
    cmp     bl, [BOARD + 0]
    jne     SHORT proc6_next_win2
    cmp     bl, [BOARD + 3]
    je      SHORT proc6_yes

  proc6_next_win2:
    cmp     bl, [BOARD + 7]
    jne     SHORT proc6_no
    cmp     bl, [BOARD + 8]
    je      SHORT proc6_yes
  proc6_no:
    ret

  proc6_yes:
    mov     rax, rbx
    ret
proc6 ENDP

proc7 PROC
    mov     bl, [BOARD + 7]
    cmp     bl, [BOARD + 1]
    jne     SHORT proc7_next_win
    cmp     bl, [BOARD + 4]
    je      SHORT proc7_yes

  proc7_next_win:
    cmp     bl, [BOARD + 6]
    jne     SHORT proc7_no
    cmp     bl, [BOARD + 8]
    je      SHORT proc7_yes
  proc7_no:
    ret

  proc7_yes:
    mov     rax, rbx
    ret
proc7 ENDP

proc8 PROC
    mov     bl, [BOARD + 8]
    cmp     bl, [BOARD + 0]
    jne     SHORT proc8_next_win
    cmp     bl, [BOARD + 4]
    je      SHORT proc8_yes

  proc8_next_win:
    cmp     bl, [BOARD + 2]
    jne     SHORT proc8_next_win2
    cmp     bl, [BOARD + 5]
    je      SHORT proc8_yes

  proc8_next_win2:
    cmp     bl, [BOARD + 6]
    jne     SHORT proc8_no
    cmp     bl, [BOARD + 7]
    je      SHORT proc8_yes
  proc8_no:
    ret

  proc8_yes:
    mov     rax, rbx
    ret
proc8 ENDP

winner_proc PROC
    ; proc* calls below assumes rax and rdx are initialized to 0

    xor     rax, rax
    xor     rdx, rdx
    lea     rbx, [WINPROCS]
    call    QWORD PTR[ rbx + rcx * 8 ]
    ret
winner_proc ENDP

winner_all PROC
    xor     rax, rax

    ; grab the upper left and test the two non-diagonal winning positions. Top row and left column

    mov     al, [BOARD]
    cmp     al, 0
    je      win_right_column
    cmp     al, [BOARD + 1]
    jne     win_left_column
    cmp     al, [BOARD + 2]
    jne     win_left_column
    ret

  win_left_column:
    cmp     al, [BOARD + 3]
    jne     win_right_column
    cmp     al, [BOARD + 6]
    jne     win_right_column
    ret

  ; grab the lower right and test the two non-diagonal winning positions. Bottom row and right column.

  win_right_column:
    mov     al, [BOARD + 8]
    cmp     al, 0
    je      win_diag1
    cmp     al, [BOARD + 2]
    jne     win_bottom_row
    cmp     al, [BOARD + 5]
    jne     win_bottom_row
    ret

  win_bottom_row:
    cmp     al, [BOARD + 6]
    jne     win_diag1
    cmp     al, [BOARD + 7]
    jne     win_diag1
    ret

  ; grab the center tile and test the 4 possible winning positions if it's not zero

  win_diag1:
    mov     al, [BOARD + 4]
    cmp     al, 0
    je      win_nobody
    cmp     al, [BOARD]
    jne     win_diag2
    cmp     al, [BOARD + 8]
    jne     win_diag2
    ret

  win_diag2:
    cmp     al, [BOARD + 2]
    jne     win_vert_middle
    cmp     al, [BOARD + 6]
    jne     win_vert_middle
    ret

  win_vert_middle:
    cmp     al, [BOARD + 1]
    jne     win_horiz_middle
    cmp     al, [BOARD + 7]
    jne     win_horiz_middle
    ret

  win_horiz_middle:
    cmp     al, [BOARD + 3]
    jne     win_nobody
    cmp     al, [BOARD + 5]
    je      win_done

  win_nobody:
    xor     rax, rax

  win_done:
    ret
winner_all ENDP

; Store the first 8 positions in rcx and the 9th in dl. Work from registers, not memory locations.

winner_registers PROC
    xor     rax, rax

    ; grab the upper left and test the two non-diagonal winning positions. Top row and left column

    lea     rdx, BOARD
    mov     rcx, [rdx]
    mov     dl, [BOARD + 8]

    mov     al, cl
    cmp     al, 0
    je      win2_right_column
    mov     rbx, rcx
    shr     rbx, 1 * 8
    cmp     al, bl
    jne     win2_left_column
    shr     rbx, 1 * 8
    cmp     al, bl
    jne     win2_left_column
    ret

  win2_left_column:
    mov     rbx, rcx
    shr     rbx, 3 * 8
    cmp     al, bl
    jne     win2_right_column
    shr     rbx, 3 * 8
    cmp     al, bl
    jne     win2_right_column
    ret

  ; grab the lower right and test the two non-diagonal winning positions. Bottom row and right column.

  win2_right_column:
    mov     al, dl
    cmp     al, 0
    je      win2_diag1
    mov     rbx, rcx
    shr     rbx, 2 * 8
    cmp     al, bl
    jne     win2_bottom_row
    shr     rbx, 3 * 8
    cmp     al, bl
    jne     win2_bottom_row
    ret

  win2_bottom_row:
    mov     rbx, rcx
    shr     rbx, 6 * 8
    cmp     al, bl
    jne     win2_diag1
    shr     rbx, 1 * 8
    cmp     al, bl
    jne     win2_diag1
    ret

  ; grab the center tile and test the 4 possible winning positions if it's not zero

  win2_diag1:
    mov     rbx, rcx
    shr     rbx, 4 * 8
    mov     al, bl
    cmp     al, 0
    je      win2_nobody
    cmp     al, cl
    jne     win2_diag2
    cmp     al, dl
    jne     win2_diag2
    ret

  win2_diag2:
    mov     rbx, rcx
    shr     rbx, 2 * 8
    cmp     al, bl
    jne     win2_vert_middle
    shr     rbx, 4 * 8
    cmp     al, bl
    jne     win2_vert_middle
    ret

  win2_vert_middle:
    mov     rbx, rcx
    shr     rbx, 1 * 8
    cmp     al, bl
    jne     win2_horiz_middle
    shr     rbx, 6 * 8
    cmp     al, bl
    jne     win2_horiz_middle
    ret

  win2_horiz_middle:
    mov     rbx, rcx
    shr     rbx, 3 * 8
    cmp     al, bl
    jne     win2_nobody
    shr     rbx, 2 * 8
    cmp     al, bl
    je      win2_done

  win2_nobody:
    xor     rax, rax

  win2_done:
    ret
winner_registers ENDP

End

