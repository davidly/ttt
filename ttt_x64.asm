;
; Prove that you can't win at tic-tac-toe
; The g++ compiler generates better code in that the loop is unrolled and the minimize/maximize codepaths
; in the loop are separated. It's almost (9 * 2) = 18x as much code, but it's 25% faster.
;

extern ExitProcess: PROC
extern printf: PROC
extern puts: PROC
extern mainCRTStartup: PROC
extern QueryPerformanceCounter: PROC
extern QueryPerformanceFrequency: PROC

; these short/terrible names are to support portability of names to 8085

XSCO    equ     9       ; maximum score
NSCO    equ     2       ; minimum score
WSCO    equ     6       ; winning score
TSCO    equ     5       ; tie score
LSCO    equ     4       ; losing score
XPIECE  equ     1       ; X move piece
OPIECE  equ     2       ; Y move piece

; local variable offsets [rbp - X] where X = 1 to N where N is the number of QWORDS beyond 4 reserved at entry
; These are for the functions minmax_min and minmax_max
V_OFFSET      equ 8 * 1            ; the value of a board position
I_OFFSET      equ 8 * 2            ; i in the for loop 0..8

; spill offsets -- [rbp + X] where X = 2..5  Spill referrs to saving parameters in registers to memory when needed
; these registers can be spilled: rcx, rdx, r8, r9
; These are for the function minmax()
A_S_OFFSET      equ 8 * 2        ; alpha
B_S_OFFSET      equ 8 * 3        ; beta

.data
    BOARD    db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; allocate 16 bytes; only first 9 are used.
    caption  db      'Hello world!', 0
    fmtStr   db      'Format string int %I64d %I64d %I64d %I64d %I64d %s', 0
    pieceS   db      '%d', 0
    intS     db      '%d ', 0
    STRWIN   db      'winner: %d', 10, 13, 0
    moveStr  db      'moves: %d', 10, 13, 0
    dbgcw    db      'calling winner', 10, 13, 0
    CRLF     db      10, 13, 0
    WINPROCS      dq     proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8
    WINPROCS_orig dq     proc0_orig, proc1_orig, proc2_orig, proc3_orig, proc4_orig, proc5_orig, proc6_orig, proc7_orig, proc8_orig
    startTime     dq     0
    endTime       dq     0
    perfFrequency dq     0
    runTime       db     'runtime in microseconds (-6): %lld', 10, 13, 0

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

    lea     rcx, [startTime]
    call    QueryPerformanceCounter

    xor     r13, r13           ; count of moves examined (calls to minmax()). Global for whole app

;     mov     r15, 1
    mov     r15, 100000         ; # of iterations

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

    ; show the time taken for the computation
    lea      rcx, [endTime]
    call     QueryPerformanceCounter
    lea      rcx, [perfFrequency]
    call     QueryPerformanceFrequency
    mov      rbx, [startTime]
    mov      rax, [endTime]
    sub      rax, rbx
    mov      rcx, [perfFrequency]
    xor      rdx, rdx
    mov      rbx, 1000000  ; increase resolution so the divide gives better results
    mul      rbx
    div      rcx

    mov      rdx, rax
    lea      rcx, [runTime]
    call     printf

    ; show the # of moves taken, mostly to validate it worked. Should be a multiple of 6493.
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
    mov     rcx, NSCO     ; alpha -- minimum score
    mov     rdx, XSCO     ; beta -- maximum score
    xor     r8, r8        ; depth

    call    minmax_min

;    mov     rdx, rax     ; return value
;    lea     rcx, STRWIN
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

; Odd depth = maximize for X in subsequent moves, O's move
minmax_max PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48                         ; 32 by convention + space for 2 8-byte local variables

    ; rcx = alpha, rdx = beta, r8 = depth. Store in spill locations reserved by parent stack
    ; r9 = position of last piece added 0..8. Keep in the register because it's used right away
    ; r10: unused
    ; r11: unused
    ; r12: i in the for loop
    ; r13: global minmax_max call count
    ; r14: V
    ; r15: reserved for global loop of 10000 calls

    inc     r13                             ; r13 is a global variable with the # of calls to minmax_max

    ; NOTE: r8, rcx, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     SHORT minmax_max_skip_winner

    ; winner_proc is inlined here
    mov     rax, 0                          ; the win procs expect rax to be 0
    mov     rbx, OPIECE                     ; and rbx to contain the player with the latest move
    lea     rsi, [WINPROCS]
    call    QWORD PTR[ rsi + r9 * 8 ]       ; winprocs is faster than winner_all and winner_registers

    cmp     al, OPIECE                      ; did O win?
    mov     rax, LSCO                       ; wasted mov if not equal, but it often saves a jump. no cmov for loading register with constant
    je      minmax_max_done

  minmax_max_skip_winner:
    mov     [rbp + A_S_OFFSET ], rcx        ; alpha
    mov     [rbp + B_S_OFFSET ], rdx        ; beta

    mov     r14, NSCO                       ; minimum possible score

    mov     r9, 0                           ; r9 is I in the for loop 0..8

  minmax_max_loop:
    lea     rdi, [BOARD]                    ; Check if the board position is unused
    add     rdi, r9
    cmp     BYTE PTR [rdi], 0
    jne     SHORT minmax_max_loopend        ; move to the next spot on the board

    mov     BYTE PTR [rdi], XPIECE          ; make the move

    ; prepare arguments for recursing
    ; read from stack spill locations, not local variable locations

    mov     rcx, [rbp + A_S_OFFSET]         ; alpha
    mov     rdx, [rbp + B_S_OFFSET]         ; beta
    inc     r8                              ; next depth 1..8
    mov     [rbp - I_OFFSET], r9            ; save i -- the for loop variable
    mov     [rbp - V_OFFSET], r14           ; save V -- value of the current board position

    call    minmax_min                      ; score is in rax on return

    dec     r8                              ; restore depth to the current level
    mov     r9, [rbp - I_OFFSET]            ; restore i
    lea     rcx, [BOARD]                    ; Restore the move on the board to 0 from X or O
    mov     BYTE PTR [rcx + r9], 0

    ; Maximize the score
    cmp     rax, WSCO
    je      SHORT minmax_max_done           ; can't do better than winning score when maximizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with V
    cmovg   r14, rax                        ; keep latest V in r14

    mov     rax, [rbp + A_S_OFFSET]         ; load alpha
    cmp     rax, r14                        ; compare alpha with V
    cmovl   rax, r14                        ; only update alpha if alpha is less than V

    cmp     rax, [rbp + B_S_OFFSET]         ; compare alpha (rax) with beta (in memory)
    jge     SHORT minmax_max_loadv_done     ; alpha pruning

    mov     [rbp + A_S_OFFSET], rax         ; update alpha with V or the same alpha value (to avoid a jump). no cmov for writing to memory

  minmax_max_loopend:                       ; bottom of the loop
    inc     r9
    cmp     r9, 9
    jl      minmax_max_loop

  minmax_max_loadv_done:
    mov     rax, r14                        ; load V then return

  minmax_max_done:
    leave
    ret
minmax_max ENDP

; Even depth = mininize for X in subsequent moves, X's move
minmax_min PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48                         ; 32 by convention + space for 2 8-byte local variables

    ; rcx = alpha, rdx = beta, r8 = depth. Store in spill locations reserved by parent stack
    ; r9 = position of last piece added 0..8. Keep in the register because it's used right away
    ;      later, r9 is the i in the for loop 0..8
    ; r10: unused
    ; r11: unused
    ; r12: unused
    ; r13: global minmax call count
    ; r14: V
    ; r15: reserved for global loop of 10000 calls

    inc     r13                             ; r13 is a global variable with the # of calls to minmax

    ; NOTE: r8, rcx, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     SHORT minmax_min_skip_winner

    ; winner_proc is inlined here
    mov     rax, 0                          ; the win procs expect rax to be 0
    mov     rbx, XPIECE                     ; and rbx to contain the player with the latest move
    lea     rsi, [WINPROCS]
    call    QWORD PTR[ rsi + r9 * 8 ]       ; winprocs is faster than winner_all and winner_registers

    cmp     al, XPIECE                      ; did X win? 
    mov     rax, WSCO                       ; wasted mov, but it often saves a jump. no cmov for loading constant to register
    je      minmax_min_done

    cmp     r8, 8                           ; recursion can only go 8 deep before the board is full
    mov     rax, TSCO                       ; wasted mov, but it often saves a jump
    je      minmax_min_done

  minmax_min_skip_winner:
    mov     [rbp + A_S_OFFSET ], rcx        ; alpha
    mov     [rbp + B_S_OFFSET ], rdx        ; beta
 
    mov     r14, XSCO                       ; maximum possible score

    mov     r9, 0                           ; r9 is I in the for loop 0..8

  minmax_min_loop:
    lea     rdi, [BOARD]                    ; Check if the board position is unused
    add     rdi, r9
    cmp     BYTE PTR [rdi], 0
    jne     SHORT minmax_min_loopend        ; move to the next spot on the board

    mov     BYTE PTR [rdi], OPIECE          ; make the move

    ; prepare arguments for recursing
    ; read from stack spill locations, not local variable locations

    mov     rcx, [rbp + A_S_OFFSET]         ; alpha
    mov     rdx, [rbp + B_S_OFFSET]         ; beta
    inc     r8                              ; next depth 1..8
    mov     [rbp - I_OFFSET], r9            ; save i -- the for loop variable
    mov     [rbp - V_OFFSET], r14           ; save V -- value of the current board position

    call    minmax_max                      ; score is in rax on return

    dec     r8                              ; restore depth to the current level
    mov     r9, [rbp - I_OFFSET]            ; restore i
    lea     rcx, [BOARD]                    ; Restore the move on the board to 0 from X or O
    mov     BYTE PTR [rcx + r9], 0

    ; Mimimize the score
    cmp     rax, LSCO
    je      SHORT minmax_min_done           ; can't do better than losing score when minimizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with v
    cmovl   r14, rax                        ; keep latest V in r14

    mov     rax, [rbp + B_S_OFFSET]         ; load beta
    cmp     rax, r14                        ; compare beta with V
    cmovg   rax, r14                        ; if V is less than Beta, update Beta

    cmp     rax, [rbp + A_S_OFFSET ]        ; compare beta (rax) with alpha (in memory)
    jle     SHORT minmax_min_loadv_done     ; beta pruning

    mov     [rbp + B_S_OFFSET], rax         ; update beta with a new value or the same value (to avoid a jump). no cmov for writing to memory

  minmax_min_loopend:                       ; bottom of the loop
    inc     r9
    cmp     r9, 9
    jl      minmax_min_loop

  minmax_min_loadv_done:
    mov     rax, r14                        ; load V then return

  minmax_min_done:
    leave
    ret
minmax_min ENDP

proc0_orig PROC
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
proc0_orig ENDP

proc0 PROC
    cmp     bl, [BOARD + 1]
    je      SHORT proc0_maybe
  proc0_next:
    cmp     bl, [BOARD + 3]
    je      SHORT proc0_maybe2
  proc0_next2:
    cmp     bl, [BOARD + 4]
    je      SHORT proc0_maybe3
    ret

  proc0_maybe:
    cmp     bl, [BOARD + 2]
    je      SHORT proc0_yes
    jmp     SHORT proc0_next

  proc0_maybe2:
    cmp     bl, [BOARD + 6]
    je      SHORT proc0_yes
    jmp     SHORT proc0_next2

  proc0_maybe3:
    cmp     bl, [BOARD + 8]
    cmovz   rax, rbx
    ret

  proc0_yes:
    mov rax, rbx
    ret
proc0 ENDP

proc1_orig PROC
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
proc1_orig ENDP

proc1 PROC
    cmp     bl, [BOARD + 0]
    je      SHORT proc1_maybe
    cmp     bl, [BOARD + 4]
    je      SHORT proc1_maybe2
    ret

  proc1_maybe:
    cmp     bl, [BOARD + 2]
    je      SHORT proc1_yes
    cmp     bl, [BOARD + 4]
    je      SHORT proc1_maybe2
    ret

  proc1_maybe2:
    cmp     bl, [BOARD + 7]
    cmovz   rax, rbx
    ret

  proc1_yes:
    mov rax, rbx
    ret
proc1 ENDP

proc2_orig PROC
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
proc2_orig ENDP

proc2 PROC
    cmp     bl, [BOARD + 0]
    je      SHORT proc2_maybe
  proc2_next:
    cmp     bl, [BOARD + 5]
    je      SHORT proc2_maybe2
  proc2_next2:
    cmp     bl, [BOARD + 4]
    je      SHORT proc2_maybe3
    ret

  proc2_maybe:
    cmp     bl, [BOARD + 1]
    je      SHORT proc2_yes
    jmp     SHORT proc2_next

  proc2_maybe2:
    cmp     bl, [BOARD + 8]
    je      SHORT proc2_yes
    jmp     SHORT proc2_next2

  proc2_maybe3:
    cmp     bl, [BOARD + 6]
    cmovz   rax, rbx
    ret

  proc2_yes:
    mov rax, rbx
    ret
proc2 ENDP

proc3_orig PROC
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
proc3_orig ENDP

proc3 PROC
    cmp     bl, [BOARD + 0]
    je      SHORT proc3_maybe
    cmp     bl, [BOARD + 4]
    je      SHORT proc3_maybe2
    ret

  proc3_maybe:
    cmp     bl, [BOARD + 6]
    je      SHORT proc3_yes
    cmp     bl, [BOARD + 4]
    je      SHORT proc3_maybe2
    ret

  proc3_maybe2:
    cmp     bl, [BOARD + 5]
    cmovz   rax, rbx
    ret

  proc3_yes:
    mov rax, rbx
    ret
proc3 ENDP

proc4_orig PROC
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
proc4_orig ENDP

proc4 PROC
    cmp     bl, [BOARD + 0]
    je      SHORT proc4_maybe
  proc4_next:
    cmp     bl, [BOARD + 3]
    je      SHORT proc4_maybe2
  proc4_next2:
    cmp     bl, [BOARD + 6]
    je      SHORT proc4_maybe3
  proc4_next3:
    cmp     bl, [BOARD + 1]
    je      SHORT proc4_maybe4
    ret

  proc4_maybe:
    cmp     bl, [BOARD + 8]
    je      SHORT proc4_yes
    jmp     SHORT proc4_next

  proc4_maybe2:
    cmp     bl, [BOARD + 5]
    je      SHORT proc4_yes
    jmp     SHORT proc4_next2

  proc4_maybe3:
    cmp     bl, [BOARD + 2]
    je      SHORT proc4_yes
    jmp     SHORT proc4_next3

  proc4_maybe4:
    cmp     bl, [BOARD + 7]
    cmovz   rax, rbx
    ret

  proc4_yes:
    mov rax, rbx
    ret
proc4 ENDP

proc5_orig PROC
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
proc5_orig ENDP

proc5 PROC
    cmp     bl, [BOARD + 2]
    je      SHORT proc5_maybe
    cmp     bl, [BOARD + 4]
    je      SHORT proc5_maybe2
    ret

  proc5_maybe:
    cmp     bl, [BOARD + 8]
    je      SHORT proc5_yes
    cmp     bl, [BOARD + 4]
    je      SHORT proc5_maybe2
    ret

  proc5_maybe2:
    cmp     bl, [BOARD + 3]
    cmovz   rax, rbx
    ret

  proc5_yes:
    mov rax, rbx
    ret
proc5 ENDP

proc6_orig PROC
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
proc6_orig ENDP

proc6 PROC
    cmp     bl, [BOARD + 0]
    je      SHORT proc6_maybe
  proc6_next:
    cmp     bl, [BOARD + 7]
    je      SHORT proc6_maybe2
  proc6_next2:
    cmp     bl, [BOARD + 4]
    je      SHORT proc6_maybe3
    ret

  proc6_maybe:
    cmp     bl, [BOARD + 3]
    je      SHORT proc6_yes
    jmp     SHORT proc6_next

  proc6_maybe2:
    cmp     bl, [BOARD + 8]
    je      SHORT proc6_yes
    jmp     SHORT proc6_next2

  proc6_maybe3:
    cmp     bl, [BOARD + 2]
    cmovz   rax, rbx
    ret

  proc6_yes:
    mov rax, rbx
    ret
proc6 ENDP

proc7_orig PROC
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
proc7_orig ENDP

proc7 PROC
    cmp     bl, [BOARD + 1]
    je      SHORT proc7_maybe
    cmp     bl, [BOARD + 6]
    je      SHORT proc7_maybe2
    ret

  proc7_maybe:
    cmp     bl, [BOARD + 4]
    je      SHORT proc7_yes
    cmp     bl, [BOARD + 6]
    je      SHORT proc7_maybe2
    ret

  proc7_maybe2:
    cmp     bl, [BOARD + 8]
    cmovz   rax, rbx
    ret

  proc7_yes:
    mov rax, rbx
    ret
proc7 ENDP

proc8_orig PROC
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
proc8_orig ENDP

proc8 PROC
    cmp     bl, [BOARD + 2]
    je      SHORT proc8_maybe
  proc8_next:
    cmp     bl, [BOARD + 6]
    je      SHORT proc8_maybe2
  proc8_next2:
    cmp     bl, [BOARD + 4]
    je      SHORT proc8_maybe3
    ret

  proc8_maybe:
    cmp     bl, [BOARD + 5]
    je      SHORT proc8_yes
    jmp     SHORT proc8_next

  proc8_maybe2:
    cmp     bl, [BOARD + 7]
    je      SHORT proc8_yes
    jmp     SHORT proc8_next2

  proc8_maybe3:
    cmp     bl, [BOARD + 0]
    cmovz   rax, rbx
    ret

  proc8_yes:
    mov rax, rbx
    ret
proc8 ENDP

End

