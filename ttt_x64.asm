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
V_OFFSET      equ 8 * 1
I_OFFSET      equ 8 * 2
SC_OFFSET     equ 8 * 3
PM_OFFSET     equ 8 * 4
MOVE_OFFSET   equ 8 * 5

; spill offsets -- [rbp + X] where X = 2..5  Spill referrs to saving parameters in registers to memory when needed
; these registers can be spilled: rcx, rdx, r8, r9
A_S_OFFSET      equ 8 * 2
B_S_OFFSET      equ 8 * 3
DEPTH_S_OFFSET  equ 8 * 4

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

    ; cx = alpha, dx = beta, r8 = depth. Store in spill locations reserved by parent stack
    ; r9 = position of last piece added. Keep in the register because it's used right away
    mov     [rbp + A_S_OFFSET ], rcx        ; alpha
    mov     [rbp + B_S_OFFSET ], rdx        ; beta
    mov     [rbp + DEPTH_S_OFFSET ], r8     ; depth
    mov     r14, r8                         ; keep depth in r14 for convenience

    inc     r13

    cmp     r14, 3                          ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     skip_winner

    mov     rcx, r9                         ; position of last piece added
    call    winner_proc                     ; winner_all is slightly faster than winner_registers. winner_proc is fastest.

    cmp     al, XPIECE
    jne     SHORT not_x_winner
    mov     rax, WSCO
    jmp     minmax_done

  not_x_winner:
    cmp     al, OPIECE
    jne     SHORT check_bottom
    mov     rax, LSCO
    jmp     minmax_done

  check_bottom:
    cmp     r14, 8                      ; recursion can only go 8 deep before the board is full
    jne     SHORT skip_winner
    mov     rax, TSCO
    jmp     minmax_done

  skip_winner:

    and     r14d, 1
    jz      minmax_minimize

    mov     rax, NSCO
    mov     [rbp - V_OFFSET], rax       ; V -- value
    mov     rax, XPIECE
    mov     [rbp - PM_OFFSET], rax      ; PM -- player move
    jmp     minmax_for

  minmax_minimize:
    mov     rax, XSCO
    mov     [rbp - V_OFFSET], rax       ; V -- value
    mov     rax, OPIECE
    mov     [rbp - PM_OFFSET], rax      ; PM -- player move

  minmax_for:
    mov     QWORD PTR [rbp - I_OFFSET], 0   ; I -- the for loop 0..8

  minmax_loop:
    lea     rcx, [BOARD]                ; Check if the board position is unused
    add     rcx, [rbp - I_OFFSET]
    cmp     BYTE PTR [rcx], 0
    jnz     minmax_loopend

    mov     al, [rbp - PM_OFFSET]       ; load PM
    mov     [rcx], al                   ; make the move
    mov     [rbp - MOVE_OFFSET], rcx    ; save this so it doesn't have to be recomputed

    ; read from stack spill locations, not local variable locations

    mov     rcx, [rbp + A_S_OFFSET]     ; alpha
    mov     rdx, [rbp + B_S_OFFSET]     ; beta
    mov     r8, [rbp + DEPTH_S_OFFSET]  ; depth
    inc     r8                          ; next depth 1..8
    mov     r9, [rbp - I_OFFSET]        ; position just claimed 0..8

    call    minmax
    mov     [rbp - SC_OFFSET], rax      ; save the score SC, but keep it in rax as long as possible

    mov     rcx, [rbp - MOVE_OFFSET]    ; restore the move position to 0 on the board
    mov     BYTE PTR [rcx], 0

    mov     r14, [rbp + DEPTH_S_OFFSET]  ; load the depth
    and     r14, 1                       ; Is it maximize?
    jz      SHORT minmax_minscore

    cmp     rax, WSCO
    je      minmax_done                 ; can't do better than winning score when maximizing

    mov     rbx, [rbp - V_OFFSET]       ; load V
    cmp     rax, rbx
    jle     SHORT minmax_no_max
    mov     [rbp - V_OFFSET], rax       ; update V with SC
    mov     rbx, rax                    ; keep latest V in rbx

  minmax_no_max:
    mov     rax, [rbp + A_S_OFFSET]     ; load alpha
    cmp     rax, rbx                    ; compare alpha with V
    jge     SHORT minmax_no_alpha_update
    mov     [rbp + A_S_OFFSET], rbx     ; update alpha with V
    mov     rax, rbx                    ; keep latest alpha in rax

  minmax_no_alpha_update:
    mov     rbx, [rbp + B_S_OFFSET]     ; load beta
    cmp     rax, rbx                    ; compare alpha with beta
    jge     minmax_loadv_done           ; alpha pruning
    jmp     minmax_loopend

  minmax_minscore:
    cmp     rax, LSCO
    je      minmax_done                 ; can't do better than losing score when minimizing
    mov     rbx, [rbp - V_OFFSET]       ; load V
    cmp     rax, rbx                    ; compare SC with v
    jge     minmax_no_min
    mov     [rbp - V_OFFSET], rax       ; update V with SC
    mov     rbx, rax

  minmax_no_min:
    mov     rax, [rbp + B_S_OFFSET]     ; load beta
    cmp     rax, rbx                    ; compare beta with V
    jle     minmax_no_beta_update
    mov     [rbp + B_S_OFFSET], rbx     ; update Beta with V
    mov     rax, rbx

  minmax_no_beta_update:
    cmp     rax, QWORD PTR [rbp + A_S_OFFSET ] ; compare beta (rax) with alpha (in memory)
    jle     minmax_loadv_done           ; beta pruning

  minmax_loopend:                       ; bottom of the loop
    inc     QWORD PTR [rbp - I_OFFSET ]
    cmp     QWORD PTR [rbp - I_OFFSET ], 9
    jl      minmax_loop

  minmax_loadv_done:
    mov     rax, [rbp - V_OFFSET]       ; load V to return

  minmax_done:
    leave
    ret
minmax ENDP

proc0 PROC
    mov     dl, [BOARD]
    cmp     dl, [BOARD + 1]
    jne     proc0_next_win
    cmp     dl, [BOARD + 2]
    je      SHORT proc0_yes

  proc0_next_win:
    cmp     dl, [BOARD + 3]
    jne     proc0_next_win2
    cmp     dl, [BOARD + 6]
    je      SHORT proc0_yes

  proc0_next_win2:
    cmp     dl, [BOARD + 4]
    jne     SHORT proc0_no
    cmp     dl, [BOARD + 8]
    je      SHORT proc0_yes
  proc0_no:
    ret

  proc0_yes:
    mov     rax, rdx
    ret
proc0 ENDP

proc1 PROC
    mov     dl, [BOARD + 1]
    cmp     dl, [BOARD + 0]
    jne     SHORT proc1_next_win
    cmp     dl, [BOARD + 2]
    je      SHORT proc1_yes

  proc1_next_win:
    cmp     dl, [BOARD + 4]
    jne     SHORT proc1_no
    cmp     dl, [BOARD + 7]
    je      SHORT proc1_yes
  proc1_no:
    ret

  proc1_yes:
    mov     rax, rdx
    ret
proc1 ENDP

proc2 PROC
    mov     dl, [BOARD + 2]
    cmp     dl, [BOARD + 0]
    jne     SHORT proc2_next_win
    cmp     dl, [BOARD + 1]
    je      SHORT proc2_yes

  proc2_next_win:
    cmp     dl, [BOARD + 5]
    jne     SHORT proc2_next_win2
    cmp     dl, [BOARD + 8]
    je      SHORT proc2_yes

  proc2_next_win2:
    cmp     dl, [BOARD + 4]
    jne     SHORT proc2_no
    cmp     dl, [BOARD + 6]
    je      SHORT proc2_yes
  proc2_no:
    ret

  proc2_yes:
    mov     rax, rdx
    ret
proc2 ENDP

proc3 PROC
    mov     dl, [BOARD + 3]
    cmp     dl, [BOARD + 4]
    jne     SHORT proc3_next_win
    cmp     dl, [BOARD + 5]
    je      SHORT proc3_yes

  proc3_next_win:
    cmp     dl, [BOARD + 0]
    jne     SHORT proc3_no
    cmp     dl, [BOARD + 6]
    je      SHORT proc3_yes
  proc3_no:
    ret

  proc3_yes:
    mov     rax, rdx
    ret
proc3 ENDP

proc4 PROC
    mov     dl, [BOARD + 4]
    cmp     dl, [BOARD + 0]
    jne     SHORT proc4_next_win
    cmp     dl, [BOARD + 8]
    je      SHORT proc4_yes

  proc4_next_win:
    cmp     dl, [BOARD + 2]
    jne     SHORT proc4_next_win2
    cmp     dl, [BOARD + 6]
    je      SHORT proc4_yes

  proc4_next_win2:
    cmp     dl, [BOARD + 1]
    jne     SHORT proc4_next_win3
    cmp     dl, [BOARD + 7]
    je      SHORT proc4_yes

  proc4_next_win3:
    cmp     dl, [BOARD + 3]
    jne     SHORT proc4_no
    cmp     dl, [BOARD + 5]
    je      SHORT proc4_yes
  proc4_no:
    ret

  proc4_yes:
    mov     rax, rdx
    ret
proc4 ENDP

proc5 PROC
    mov     dl, [BOARD + 5]
    cmp     dl, [BOARD + 3]
    jne     SHORT proc5_next_win
    cmp     dl, [BOARD + 4]
    je      SHORT proc5_yes

  proc5_next_win:
    cmp     dl, [BOARD + 2]
    jne     SHORT proc5_no
    cmp     dl, [BOARD + 8]
    je      SHORT proc5_yes
  proc5_no:
    ret

  proc5_yes:
    mov     rax, rdx
    ret
proc5 ENDP

proc6 PROC
    mov     dl, [BOARD + 6]
    cmp     dl, [BOARD + 7]
    jne     SHORT proc6_next_win
    cmp     dl, [BOARD + 8]
    je      SHORT proc6_yes

  proc6_next_win:
    cmp     dl, [BOARD + 0]
    jne     SHORT proc6_next_win2
    cmp     dl, [BOARD + 3]
    je      SHORT proc6_yes

  proc6_next_win2:
    cmp     dl, [BOARD + 4]
    jne     SHORT proc6_no
    cmp     dl, [BOARD + 2]
    je      SHORT proc6_yes
  proc6_no:
    ret

  proc6_yes:
    mov     rax, rdx
    ret
proc6 ENDP

proc7 PROC
    mov     dl, [BOARD + 7]
    cmp     dl, [BOARD + 6]
    jne     SHORT proc7_next_win
    cmp     dl, [BOARD + 8]
    je      SHORT proc7_yes

  proc7_next_win:
    cmp     dl, [BOARD + 1]
    jne     SHORT proc7_no
    cmp     dl, [BOARD + 4]
    je      SHORT proc7_yes
  proc7_no:
    ret

  proc7_yes:
    mov     rax, rdx
    ret
proc7 ENDP

proc8 PROC
    mov     dl, [BOARD + 8]
    cmp     dl, [BOARD + 6]
    jne     SHORT proc8_next_win
    cmp     dl, [BOARD + 7]
    je      SHORT proc8_yes

  proc8_next_win:
    cmp     dl, [BOARD + 2]
    jne     SHORT proc8_next_win2
    cmp     dl, [BOARD + 5]
    je      SHORT proc8_yes

  proc8_next_win2:
    cmp     dl, [BOARD + 0]
    jne     SHORT proc8_no
    cmp     dl, [BOARD + 4]
    je      SHORT proc8_yes
  proc8_no:
    ret

  proc8_yes:
    mov     rax, rdx
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

