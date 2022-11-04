;
; Prove that you can't win at tic-tac-toe.
; This code just separates min/max codepaths but doesn't unroll the loops.
; I only tried to optimize for what a C++ compiler could reasonably do with the source code.
; Lots of other optimizations are possible beyond what the compiler could reasonably implement.
; g++ (best of the compiled versions): 0.0408
; Initial with decent optimizations: .0772
; lots of small fixes using registers instead of memory: .0578
; separating min/max codepaths, aligning loop jump targets: .0448
; separate loops for 3 boards instead of just one .0433
; better alignment, keep alpha/beta in registers: .0404
; remove jumps, alternate WINPROCS_X and WINPROCS: .0350
; use 3 cores: .0138
;
; Board: 0 | 1 | 2
;        ---------
;        3 | 4 | 5
;        ---------
;        6 | 7 | 8
;
; Only first moves 0, 1, and 4 are solved since other first moves are reflections

extern printf: PROC
extern QueryPerformanceCounter: PROC
extern QueryPerformanceFrequency: PROC
extern CreateThread: PROC
extern ResumeThread: PROC
extern WaitForSingleObject: PROC
extern WaitForMultipleObjects: PROC
extern CloseHandle: PROC

; these short/terrible names are to support portability of names to 8085

XSCO    equ     9                        ; maximum score
NSCO    equ     2                        ; minimum score
WSCO    equ     6                        ; winning score
TSCO    equ     5                        ; tie score
LSCO    equ     4                        ; losing score
XPIECE  equ     1                        ; X move piece
OPIECE  equ     2                        ; O move piece
                                         
; local variable offsets [rbp - X] where X = 1 to N where N is the number of QWORDS beyond 4 reserved at entry
; These are for the functions minmax_min and minmax_max
V_OFFSET      equ 8 * 1                  ; the value of a board position
I_OFFSET      equ 8 * 2                  ; i in the for loop 0..8

; spill offsets -- [rbp + X] where X = 2..5  Spill referrs to saving parameters in registers to memory when needed
; these registers can be spilled: rcx, rdx, r8, r9
; Locations 0 (prior rbp) and 1 (return address) are reserved.
; These are for the functions minmax_min and minmax_max
A_S_OFFSET      equ 8 * 2                ; alpha
B_S_OFFSET      equ 8 * 3                ; beta

data_ttt SEGMENT ALIGN( 4096 ) 'DATA'
    ; It's important to put each of these boards in separate 64-byte cache lines or multi-core performance is terrible
    ; For some Intel CPUs 256 bytes is required, like the i5-2430M, i7-4770K, and i7-5820K
    BOARD0        db     1,0,0,0,0,0,0,0,0
  align 256 ; 64
    BOARD1        db     0,1,0,0,0,0,0,0,0
  align 256 ; 64
    BOARD4        db     0,0,0,0,1,0,0,0,0
  align 256 ;
    ; using either _X or _O and WINPROCS is fastest. Using both _ versions or neither is slower. I don't know why
    WINPROCS_X    dq     proc0_X, proc1_X, proc2_X, proc3_X, proc4_X, proc5_X, proc6_X, proc7_X, proc8_X
  align 64
    WINPROCS_O    dq     proc0_O, proc1_O, proc2_O, proc3_O, proc4_O, proc5_O, proc6_O, proc7_O, proc8_O
  align 64
    WINPROCS_NJ   dq     proc0_nj, proc1_nj, proc2_nj, proc3_nj, proc4_nj, proc5_nj, proc6_nj, proc7_nj, proc8_nj ; nj for No Jump when no win
  align 64
    WINPROCS      dq     proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8
  align 64
    runTime       db     'runtime in microseconds (-6): %lld', 10, 13, 0
    caption       db     'Hello world!', 0
    fmtStr        db     'Format string int %I64d %I64d %I64d %I64d %I64d %s', 0
    pieceS        db     '%d', 0
    intS          db     '%d ', 0
    STRWIN        db     'winner: %d', 10, 13, 0
    moveStr       db     'moves: %d', 10, 13, 0
    donewith      db     'done with: %d', 10, 13, 0
    dbgcw         db     'calling winner', 10, 13, 0
    CRLF          db     10, 13, 0
  align 64
    startTime     dq     0
    endTime       dq     0
    perfFrequency dq     0
    moveCount     dq     0
data_ttt ENDS

code_ttt SEGMENT ALIGN( 4096 ) 'CODE'
main PROC ; linking with the C runtime, so main will be invoked
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 4

;    lea    rcx, [fmtStr]
;    mov    rdx, 17
;    mov    r8, 18
;    mov    r9, 19
;    mov    rbx, 20
;    mov    [rsp + 8 * 4 ], rbx
;    mov    rbx, 21
;    mov    [rsp + 8 * 5 ], rbx
;    lea    rbx, [caption]
;    mov    [rsp + 8 * 6 ], rbx
;    call   printf

    ; solve for the 3 unique starting board positions in serial

    mov     [moveCount], 0               ; # of calls to minmax_* functions
    lea     rcx, [startTime]
    call    QueryPerformanceCounter

    mov     rcx, 0                       ; solve for board 0
    call    TTTThreadProc

    mov     rcx, 1                       ; solve for board 1
    call    TTTThreadProc

    mov     rcx, 4                       ; solve for board 4
    call    TTTThreadProc

    call    showstats

    ; now do it again, but this time with 3 threads in parallel

    mov     [moveCount], 0               ; # of calls to minmax_* functions
    lea     rcx, [startTime]
    call    QueryPerformanceCounter

    call    solvethreaded

    call    showstats

    xor     rax, rax
    leave
    ret
main ENDP

showstats PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    lea     rcx, [endTime]
    call    QueryPerformanceCounter
    lea     rcx, [perfFrequency]
    call    QueryPerformanceFrequency
    mov     rbx, [startTime]
    mov     rax, [endTime]
    sub     rax, rbx                     ; rax now has total execution time in counter units
    mov     rcx, [perfFrequency]
    xor     rdx, rdx
    mov     rbx, 1000000                 ; increase resolution so the divide gives better results
    mul     rbx                          ; multiplies rdx:rax by rbx and leaves the result in rax
    div     rcx                          ; divides rdx:rax by rcx and leaves the result in rax

    mov     rdx, rax                     ; rax now has the total execution time; print it out
    lea     rcx, [runTime]
    call    printf

    ; show the # of moves taken, mostly to validate it worked. Should be a multiple of 6493.
    mov     rdx, [moveCount]
    lea     rcx, moveStr
    call    printf

    leave
    ret
showstats ENDP

boardIndex$ = 32
align 16
TTTThreadProc PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 2              ; only 40 needed, but want to keep stacks 16-byte aligned
    
    xor     r13, r13                     ; and r13 to be the move count
    
    mov     boardIndex$[rsp], rcx        ; save the initial move board position

    ; load r10 with the board to play -- BOARD0, BOARD1, or BOARD4

    cmp     rcx, 0
    jne     TTTThreadProc_try1
    lea     r10, [BOARD0]
    jmp     TTTThreadProc_for

  TTTThreadProc_try1:
    cmp     rcx, 1
    jne     TTTThreadProc_try4
    lea     r10, [BOARD1]
    jmp     TTTThreadProc_for

  TTTThreadProc_try4:                    ; don't validate it's four -- just assume it
    lea     r10, [BOARD4]
    mov     rcx, 4                       ; ensure this is the case
    mov     boardIndex$[rsp], rcx        ; again, make sure

  TTTThreadProc_for:
    mov     r15, 100000                   ; # of iterations -- 100,000

    align 16
  TTTThreadProc_loop:
    mov     rcx, NSCO                    ; alpha -- minimum score
    mov     rdx, XSCO                    ; beta -- maximum score
    xor     r8, r8                       ; depth is 0
    mov     r9, boardIndex$[rsp]         ; position of last board update

    ; r10 holds the board
    ; r13 holds the minmax call count

    call    minmax_min                   ; call min, because X just moved and now O moves should be minimized

    dec     r15
    cmp     r15, 0
    jne     TTTTHreadProc_loop

    lock add [moveCount], r13            ; do this locked update once here at the end instead of for each iteration
    xor     rax, rax

    leave
    ret
TTTThreadProc ENDP

align 16
solvethreaded PROC
  aHandles$ = 48  ; reserve 16 for 2 handles bytes. Start at 48 because < than that is reserved for CreateThread arguments
    push    rbp
    mov     rbp, rsp
    sub     rsp, 80

    ; The thread creation, waiting, and handle closing are fast; very little overall impact on performance.
    ; I tried creating the threads suspended and recording the start time just before the ResumeThread. No difference.

    ; board 1 takes the longest to compute; start it first
    xor     rcx, rcx                     ; no security attributes
    xor     rdx, rdx                     ; default stack size
    lea     r8, TTTThreadProc            ; call this function
    mov     r9, 1                        ; 0, 1, or 4 depending on the board being solved for
    mov     DWORD PTR [rsp + 32], 0      ; 0 creation flags
    mov     QWORD PTR [rsp + 40], 0      ; don't return a dwThreadID
    call    CreateThread
    mov     aHandles$[rsp], rax          ; save the thread handle

    ; board 4 takes the next longest
    xor     rcx, rcx                     ; no security attributes
    xor     rdx, rdx                     ; default stack size
    lea     r8, TTTThreadProc            ; call this function
    mov     r9, 4                        ; 0, 1, or 4 depending on the board being solved for
    mov     DWORD PTR [rsp + 32], 0      ; 0 creation flags
    mov     QWORD PTR [rsp + 40], 0      ; don't return a dwThreadID
    call    CreateThread
    mov     aHandles$[rsp + 8], rax      ; save the thread handle

    ; solve for board 0 on this thread
    mov     rcx, 0
    call    TTTThreadProc

    ; wait for the 2 created threads to complete
    mov     rcx, 2                        ; # of handles to wait for
    lea     rdx, aHandles$[rsp]           ; location of the handles
    mov     r8d, 1                        ; wait for all (true)
    mov     r9, -1                        ; wait forever, INFINITE
    call    WaitForMultipleObjects

    ; close the thread handles
    mov     rcx, aHandles$[rsp + 0]
    call    CloseHandle
    mov     rcx, aHandles$[rsp + 8]
    call    CloseHandle

    leave
    ret
solvethreaded ENDP

align 16
printCRLF PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    lea     rcx, CRLF
    call    printf

    leave
    ret
printCRLF ENDP

align 16
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

align 16
printboard PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    xor     rax, rax
    xor     rbx, rbx

  pb_loop:
    mov     rcx, r10
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

; Odd depth = maximize for X in subsequent moves, O just took a move in r9
align 16
minmax_max PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 2                 ; 32 by convention + space for 2 8-byte local variables I and V

    ; rcx: alpha. Store in spill location reserved by parent stack
    ; rdx: beta. Store in spill location reserved by parent stack
    ; r8:  depth. keep in the register
    ; r9:  position of last piece added 0..8. Keep in the register because it's used right away
    ;      later, r9 is the i in the for loop 0..8
    ; r10: the board
    ; r11: unused
    ; r12: unused except by some WINPROCS
    ; r13: global minmax call count
    ; r14: Value
    ; r15: reserved for global loop of 10000 calls

    inc     r13                             ; r13 is a global variable with the # of calls to minmax_max and minmax_min

    ; NOTE: rcx, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     SHORT minmax_max_skip_winner    ; if too few moves, there can't be a winner yet

    ; the win procs expect the board in r10
    xor     rax, rax                        ; the win procs expect rax to be 0
    mov     rbx, OPIECE                     ; and rbx to contain the player with the latest move
    lea     rsi, [WINPROCS_NJ]               
    call    QWORD PTR [rsi + r9 * 8]        ; call the proc that checks for wins starting with last piece added

    cmp     rax, OPIECE                     ; did O win?
    mov     rax, LSCO                       ; wasted mov if not equal, but it often saves a jump. no cmov for loading register with constant
    je      minmax_max_done

    align   16
  minmax_max_skip_winner:
    mov     [rbp + A_S_OFFSET], rcx         ; alpha saved in the spill location
    mov     [rbp + B_S_OFFSET], rdx         ; beta saved in the spill location

    mov     r14, NSCO                       ; minimum possible score. maximizing, so find a score higher than this
    xor     r9, r9                          ; r9 is I in the for loop 0..8
    dec     r9                              ; avoid a jump by starting at -1

    align   16
  minmax_max_top_of_loop:
    inc     r9
    cmp     r9, 9                           ; 9 because the board is 0..8
    je      SHORT minmax_max_loadv_done

    cmp     BYTE PTR [r10 + r9], 0          ; is the board position free?
    jne     SHORT minmax_max_top_of_loop    ; move to the next spot on the board

    mov     BYTE PTR [r10 + r9], XPIECE     ; make the move

    ; prepare arguments for recursing. rcx (alpha) and rdx (beta) are already set
    inc     r8                              ; next depth 1..8
    mov     [rbp - I_OFFSET], r9            ; save i -- the for loop variable
    mov     [rbp - V_OFFSET], r14           ; save V -- value of the current board position

    ; unlike win64 calling conventions, no registers are preserved aside from r8 and globals in r10, r12, r13, and r15
    call    minmax_min                      ; score is in rax on return

    dec     r8                              ; restore depth to the current level
    mov     r9, [rbp - I_OFFSET]            ; restore i
    mov     BYTE PTR [r10 + r9], 0          ; Restore the move on the board to 0 from X

    cmp     rax, WSCO
    je      SHORT minmax_max_done           ; can't do better than winning score when maximizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with V
    cmovg   r14, rax                        ; keep latest V in r14

    lea     rdi, [rbp + A_S_OFFSET]         ; save address of alpha
    mov     rcx, [rdi]                      ; load alpha
    cmp     rcx, r14                        ; compare alpha with V
    cmovl   rcx, r14                        ; only update alpha if alpha is less than V

    mov     rdx, [rbp + B_S_OFFSET]         ; load beta
    cmp     rcx, rdx                        ; compare alpha (rcx) with beta (rdx)
    jge     SHORT minmax_max_loadv_done     ; alpha pruning if alpha >= beta
    mov     [rdi], rcx                      ; update alpha with V or the same alpha value (to avoid a jump). no cmov for writing to memory

    jmp     minmax_max_top_of_loop

    align   16
  minmax_max_loadv_done:
    mov     rax, r14                        ; load V then return

  minmax_max_done:
    leave
    ret
minmax_max ENDP

; Even depth = mininize for X in subsequent moves, X just took a move in r9
align 16
minmax_min PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 2                 ; 32 by convention + space for 2 8-byte local variables I and V

    ; rcx: alpha. Store in spill location reserved by parent stack
    ; rdx: beta. Store in spill location reserved by parent stack
    ; r8:  depth. keep in the register
    ; r9:  position of last piece added 0..8. Keep in the register because it's used right away
    ;      later, r9 is the i in the for loop 0..8
    ; r10: the board
    ; r11: unused
    ; r12: unused except by some WINPROCS
    ; r13: global minmax call count
    ; r14: Value
    ; r15: reserved for global loop of 10000 calls

    inc     r13                             ; r13 is a global variable with the # of calls to minmax_max and minmax_min

    ; NOTE: rcx, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     SHORT minmax_min_skip_winner    ; if too few moves, there can't be a winner yet

    ; the win procs expect the board in r10
    xor     rax, rax                        ; the win procs expect rax to be 0
    mov     rbx, XPIECE                     ; and rbx to contain the player with the latest move
    lea     rsi, [WINPROCS_X]
    call    QWORD PTR [rsi + r9 * 8]        ; call the proc that checks for wins starting with last piece added

    cmp     rax, XPIECE                     ; did X win? 
    mov     rax, WSCO                       ; wasted mov, but it often saves a jump. no cmov for loading constant to register
    je      minmax_min_done

    cmp     r8, 8                           ; recursion can only go 8 deep before the board is full
    mov     rax, TSCO                       ; wasted mov, but it often saves a jump
    je      minmax_min_done

    align   16
  minmax_min_skip_winner:
    mov     [rbp + A_S_OFFSET], rcx         ; alpha saved in the spill location
    mov     [rbp + B_S_OFFSET], rdx         ; beta saved in the spill location
 
    mov     r14, XSCO                       ; maximum possible score; minimizing, so find a score lower than this
    xor     r9, r9                          ; r9 is I in the for loop 0..8
    dec     r9                              ; avoid a jump by starting at -1

    align   16
  minmax_min_top_of_loop:
    inc     r9
    cmp     r9, 9                           ; 9 because the board is 0..8
    je      SHORT minmax_min_loadv_done

    cmp     BYTE PTR [r10 + r9], 0          ; is the board position free?
    jne     SHORT minmax_min_top_of_loop    ; move to the next spot on the board

    mov     BYTE PTR [r10 + r9], OPIECE     ; make the move

    ; prepare arguments for recursing. rcx (alpha) and rdx (beta) are already set
    inc     r8                              ; next depth 1..8
    mov     [rbp - I_OFFSET], r9            ; save i -- the for loop variable
    mov     [rbp - V_OFFSET], r14           ; save V -- value of the current board position

    ; unlike win64 calling conventions, no registers are preserved aside from r8 and globals in r10, r12, r13, and r15
    call    minmax_max                      ; score is in rax on return

    dec     r8                              ; restore depth to the current level
    mov     r9, [rbp - I_OFFSET]            ; restore i
    mov     BYTE PTR [r10 + r9], 0          ; Restore the move on the board to 0 from O

    cmp     rax, LSCO
    je      SHORT minmax_min_done           ; can't do better than losing score when minimizing

    mov     r14, [rbp - V_OFFSET]           ; load V
    cmp     rax, r14                        ; compare SC with v
    cmovl   r14, rax                        ; keep latest V in r14

    lea     rdi, [rbp + B_S_OFFSET]         ; save address of beta
    mov     rdx, [rdi]                      ; load beta
    cmp     rdx, r14                        ; compare beta with V
    cmovg   rdx, r14                        ; if V is less than Beta, update Beta

    mov     rcx, [rbp + A_S_OFFSET ]        ; load alpha
    cmp     rdx, rcx                        ; compare beta (rdx) with alpha (rcx)
    jle     SHORT minmax_min_loadv_done     ; beta pruning if beta <= alpha
    mov     [rdi], rdx                      ; update beta with a new value or the same value (to avoid a jump). no cmov for writing to memory

    jmp     minmax_min_top_of_loop

    align   16
  minmax_min_loadv_done:
    mov     rax, r14                        ; load V then return

  minmax_min_done:
    leave
    ret
minmax_min ENDP

align 16
proc0 PROC
    cmp     bl, [r10 + 1]
    jne     SHORT proc0_next_win
    cmp     bl, [r10 + 2]
    je      SHORT proc0_yes

  proc0_next_win:
    cmp     bl, [r10 + 3]
    jne     SHORT proc0_next_win2
    cmp     bl, [r10 + 6]
    je      SHORT proc0_yes

  proc0_next_win2:
    cmp     bl, [r10 + 4]
    jne     SHORT proc0_no
    cmp     bl, [r10 + 8]
    je      SHORT proc0_yes

  proc0_no:
    ret

  proc0_yes:
    mov     rax, rbx
    ret
proc0 ENDP

align 16
proc0_nj PROC
    cmp     bl, [r10 + 1]
    je      SHORT proc0_top_row2

  proc0_left_column:
    cmp     bl, [r10 + 3]
    je      SHORT proc0_left_column2

  proc0_diagonal:
    cmp     bl, [r10 + 4]
    je      SHORT proc0_diagonal2
    ret

  proc0_top_row2:
    cmp     bl, [r10 + 2]
    jne     proc0_left_column
    mov     rax, rbx
    ret

  proc0_left_column2:
    cmp     bl, [r10 + 6]
    jne     proc0_diagonal
    mov     rax, rbx
    ret

  proc0_diagonal2:
    cmp     bl, [r10 + 8]
    cmove   rax, rbx
    ret
proc0_nj ENDP

align 16
proc1 PROC
    cmp     bl, [r10 + 0]
    jne     SHORT proc1_next_win
    cmp     bl, [r10 + 2]
    je      SHORT proc1_yes

  proc1_next_win:
    cmp     bl, [r10 + 4]
    jne     SHORT proc1_no
    cmp     bl, [r10 + 7]
    je      SHORT proc1_yes

  proc1_no:
    ret

  proc1_yes:
    mov     rax, rbx
    ret
proc1 ENDP

align 16
proc1_nj PROC
    cmp     bl, [r10 + 0]
    je      SHORT proc1_top_row2

  proc1_center_column:
    cmp     bl, [r10 + 4]
    je      SHORT proc1_center_column2
    ret

  proc1_top_row2:
    cmp     bl, [r10 + 2]
    jne     SHORT proc1_center_column
    mov     rax, rbx
    ret

  proc1_center_column2:
    cmp     bl, [r10 + 7]
    cmove   rax, rbx
    ret
proc1_nj ENDP

align 16
proc2 PROC
    cmp     bl, [r10 + 0]
    jne     SHORT proc2_next_win
    cmp     bl, [r10 + 1]
    je      SHORT proc2_yes

  proc2_next_win:
    cmp     bl, [r10 + 5]
    jne     SHORT proc2_next_win2
    cmp     bl, [r10 + 8]
    je      SHORT proc2_yes

  proc2_next_win2:
    cmp     bl, [r10 + 4]
    jne     SHORT proc2_no
    cmp     bl, [r10 + 6]
    je      SHORT proc2_yes

  proc2_no:
    ret

  proc2_yes:
    mov     rax, rbx
    ret
proc2 ENDP

align 16
proc2_nj PROC
    cmp     bl, [r10 + 0]
    je      SHORT proc2_top_row2

  proc2_right_column:
    cmp     bl, [r10 + 5]
    je      SHORT proc2_right_column2

  proc2_diagonal:
    cmp     bl, [r10 + 4]
    je      SHORT proc2_diagonal2
    ret

  proc2_top_row2:
    cmp     bl, [r10 + 1]
    jne     proc2_right_column
    mov     rax, rbx
    ret

  proc2_right_column2:
    cmp     bl, [r10 + 8]
    jne     proc2_diagonal
    mov     rax, rbx
    ret

  proc2_diagonal2:
    cmp     bl, [r10 + 6]
    cmove   rax, rbx
    ret
proc2_nj ENDP

align 16
proc3 PROC
    cmp     bl, [r10 + 0]
    jne     SHORT proc3_next_win
    cmp     bl, [r10 + 6]
    je      SHORT proc3_yes

  proc3_next_win:
    cmp     bl, [r10 + 4]
    jne     SHORT proc3_no
    cmp     bl, [r10 + 5]
    je      SHORT proc3_yes

  proc3_no:
    ret

  proc3_yes:
    mov     rax, rbx
    ret
proc3 ENDP

align 16
proc3_nj PROC
    cmp     bl, [r10 + 4]
    je      SHORT proc3_center_row2

  proc3_left_column:
    cmp     bl, [r10 + 0]
    je      SHORT proc3_left_column2
    ret

  proc3_center_row2:
    cmp     bl, [r10 + 5]
    jne     SHORT proc3_left_column
    mov     rax, rbx
    ret

  proc3_left_column2:
    cmp     bl, [r10 + 6]
    cmove   rax, rbx
    ret
proc3_nj ENDP

align 16
proc4 PROC
    cmp     bl, [r10 + 0]
    jne     SHORT proc4_next_win
    cmp     bl, [r10 + 8]
    je      SHORT proc4_yes

  proc4_next_win:
    cmp     bl, [r10 + 2]
    jne     SHORT proc4_next_win2
    cmp     bl, [r10 + 6]
    je      SHORT proc4_yes

  proc4_next_win2:
    cmp     bl, [r10 + 1]
    jne     SHORT proc4_next_win3
    cmp     bl, [r10 + 7]
    je      SHORT proc4_yes

  proc4_next_win3:
    cmp     bl, [r10 + 3]
    jne     SHORT proc4_no
    cmp     bl, [r10 + 5]
    je      SHORT proc4_yes

  proc4_no:
    ret

  proc4_yes:
    mov     rax, rbx
    ret
proc4 ENDP

align 16
proc4_nj PROC
    cmp     bl, [r10 + 1]
    je      SHORT proc4_center_column2

  proc4_center_row:
    cmp     bl, [r10 + 3]
    je      SHORT proc4_center_row2

  proc4_diagonal:
    cmp     bl, [r10 + 0]
    je      SHORT proc4_diagonal2

  proc4_diagonalB:
    cmp     bl, [r10 + 2]
    je      SHORT proc4_diagonalB2
    ret

  proc4_center_column2:
    cmp     bl, [r10 + 7]
    jne     proc4_center_row
    mov     rax, rbx
    ret

  proc4_center_row2:
    cmp     bl, [r10 + 5]
    jne     proc4_diagonal
    mov     rax, rbx
    ret

  proc4_diagonal2:
    cmp     bl, [r10 + 8]
    jne     proc4_diagonalB
    mov     rax, rbx
    ret

  proc4_diagonalB2:
    cmp     bl, [r10 + 6]
    cmove   rax, rbx
    ret
proc4_nj ENDP

align 16
proc5 PROC
    cmp     bl, [r10 + 3]
    jne     SHORT proc5_next_win
    cmp     bl, [r10 + 4]
    je      SHORT proc5_yes

  proc5_next_win:
    cmp     bl, [r10 + 2]
    jne     SHORT proc5_no
    cmp     bl, [r10 + 8]
    je      SHORT proc5_yes

  proc5_no:
    ret

  proc5_yes:
    mov     rax, rbx
    ret
proc5 ENDP

align 16
proc5_nj PROC
    cmp     bl, [r10 + 4]
    je      SHORT proc5_center_row2

  proc5_right_column:
    cmp     bl, [r10 + 2]
    je      SHORT proc5_right_column2
    ret

  proc5_center_row2:
    cmp     bl, [r10 + 3]
    jne     SHORT proc5_right_column
    mov     rax, rbx
    ret

  proc5_right_column2:
    cmp     bl, [r10 + 8]
    cmove   rax, rbx
    ret
proc5_nj ENDP

align 16
proc6 PROC
    cmp     bl, [r10 + 4]
    jne     SHORT proc6_next_win
    cmp     bl, [r10 + 2]
    je      SHORT proc6_yes

  proc6_next_win:
    cmp     bl, [r10 + 0]
    jne     SHORT proc6_next_win2
    cmp     bl, [r10 + 3]
    je      SHORT proc6_yes

  proc6_next_win2:
    cmp     bl, [r10 + 7]
    jne     SHORT proc6_no
    cmp     bl, [r10 + 8]
    je      SHORT proc6_yes

  proc6_no:
    ret

  proc6_yes:
    mov     rax, rbx
    ret
proc6 ENDP

align 16
proc6_nj PROC
    cmp     bl, [r10 + 0]
    je      SHORT proc6_left_column2

  proc6_bottom_row:
    cmp     bl, [r10 + 7]
    je      SHORT proc6_bottom_row2

  proc6_diagonal:
    cmp     bl, [r10 + 4]
    je      SHORT proc6_diagonal2
    ret

  proc6_left_column2:
    cmp     bl, [r10 + 3]
    jne     proc6_bottom_row
    mov     rax, rbx
    ret

  proc6_bottom_row2:
    cmp     bl, [r10 + 8]
    jne     proc6_diagonal
    mov     rax, rbx
    ret

  proc6_diagonal2:
    cmp     bl, [r10 + 2]
    cmove   rax, rbx
    ret
proc6_nj ENDP

align 16
proc7 PROC
    cmp     bl, [r10 + 1]
    jne     SHORT proc7_next_win
    cmp     bl, [r10 + 4]
    je      SHORT proc7_yes

  proc7_next_win:
    cmp     bl, [r10 + 6]
    jne     SHORT proc7_no
    cmp     bl, [r10 + 8]
    je      SHORT proc7_yes

  proc7_no:
    ret

  proc7_yes:
    mov     rax, rbx
    ret
proc7 ENDP

align 16
proc7_nj PROC
    cmp     bl, [r10 + 6]
    je      SHORT proc7_bottom_row2

  proc7_center_column:
    cmp     bl, [r10 + 1]
    je      SHORT proc7_center_column2
    ret

  proc7_bottom_row2:
    cmp     bl, [r10 + 8]
    jne     SHORT proc7_center_column
    mov     rax, rbx
    ret

  proc7_center_column2:
    cmp     bl, [r10 + 4]
    cmove   rax, rbx
    ret
proc7_nj ENDP

align 16
proc8 PROC
    cmp     bl, [r10 + 0]
    jne     SHORT proc8_next_win
    cmp     bl, [r10 + 4]
    je      SHORT proc8_yes

  proc8_next_win:
    cmp     bl, [r10 + 2]
    jne     SHORT proc8_next_win2
    cmp     bl, [r10 + 5]
    je      SHORT proc8_yes

  proc8_next_win2:
    cmp     bl, [r10 + 6]
    jne     SHORT proc8_no
    cmp     bl, [r10 + 7]
    je      SHORT proc8_yes

  proc8_no:
    ret

  proc8_yes:
    mov     rax, rbx
    ret
proc8 ENDP

align 16
proc8_nj PROC
    cmp     bl, [r10 + 2]
    je      SHORT proc8_right_column2

  proc8_bottom_row:
    cmp     bl, [r10 + 6]
    je      SHORT proc8_bottom_row2

  proc8_diagonal:
    cmp     bl, [r10 + 4]
    je      SHORT proc8_diagonal2
    ret

  proc8_right_column2:
    cmp     bl, [r10 + 5]
    jne     proc8_bottom_row
    mov     rax, rbx
    ret

  proc8_bottom_row2:
    cmp     bl, [r10 + 7]
    jne     proc8_diagonal
    mov     rax, rbx
    ret

  proc8_diagonal2:
    cmp     bl, [r10 + 0]
    cmove   rax, rbx
    ret
proc8_nj ENDP

align 16
proc0_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020202h               ; top row OOO
    and     rdi, r12
    cmp     rdi, r12
    je      proc0_yes

    mov     rdi, rsi
    mov     r12, 02000002000002h       ; left column OOO
    and     rdi, r12
    cmp     rdi, r12
    je      proc0_yes

    cmp     bl, [r10 + 4]              ; diagnol top left to bottom right
    jne     SHORT proc0_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc0_no:
    ret

  proc0_yes:
    mov     rax, rbx
    ret
proc0_O ENDP

align 16
proc1_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020202h               ; top row OOO
    and     rdi, r12
    cmp     rdi, r12
    je      proc1_yes

    mov     rdi, rsi
    mov     r12, 0200000200000200h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc1_yes:
    mov     rax, rbx
    ret
proc1_O ENDP

align 16
proc2_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020202h               ; top row OOO
    and     rdi, r12
    cmp     rdi, r12
    je      proc2_yes

    mov     rdi, rsi
    mov     r12, 02000200020000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc2_yes

    cmp     bl, [r10 + 5]              ; right column
    jne     SHORT proc2_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc2_no:
    ret

  proc2_yes:
    mov     rax, rbx
    ret
proc2_O ENDP

align 16
proc3_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 02000002000002h       ; left column
    and     rdi, r12
    cmp     rdi, r12
    je      proc3_yes

    mov     rdi, rsi
    mov     r12, 020202000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc3_yes:
    mov     rax, rbx
    ret
proc3_O ENDP

align 16
proc4_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020202000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    mov     rdi, rsi
    mov     r12, 02000200020000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    mov     rdi, rsi
    mov     r12, 0200000200000200h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    cmp     bl, [r10 + 0]              ; diagonal top left to bottom right
    jne     SHORT proc4_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc4_no:
    ret

  proc4_yes:
    mov     rax, rbx
    ret
proc4_O ENDP

align 16
proc5_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020202000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    je      proc5_yes

    cmp     bl, [r10 + 2]              ; right column
    jne     SHORT proc5_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc5_no:
    ret

  proc5_yes:
    mov     rax, rbx
    ret
proc5_O ENDP

align 16
proc6_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 02000002000002h       ; left column
    and     rdi, r12
    cmp     rdi, r12
    je      proc6_yes

    mov     rdi, rsi
    mov     r12, 02000200020000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc6_yes

    cmp     bl, [r10 + 7]              ; bottom row
    jne     SHORT proc6_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc6_no:
    ret

  proc6_yes:
    mov     rax, rbx
    ret
proc6_O ENDP

align 16
proc7_O PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 0200000200000200h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    je      proc7_yes

    cmp     bl, [r10 + 6]              ; bottom row
    jne     SHORT proc7_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc7_no:
    ret

  proc7_yes:
    mov     rax, rbx
    ret
proc7_O ENDP

align 16
proc8_O PROC
    ; for 8, ignore the byte beyond the qword because we know its value

    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 020000020000h         ; right column
    and     rdi, r12
    cmp     rdi, r12
    je      proc8_yes

    mov     rdi, rsi
    mov     r12, 0200000002h           ; diagonal top left to bottom right
    and     rdi, r12
    cmp     rdi, r12
    je      proc8_yes

    mov     rdi, rsi
    mov     r12, 0202000000000000h     ; bottom row
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc8_yes:
    mov     rax, rbx
    ret
proc8_O ENDP

align 16
proc0_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 010101h               ; top row XXX
    and     rdi, r12
    cmp     rdi, r12
    je      proc0_yes

    mov     rdi, rsi
    mov     r12, 01000001000001h       ; left column XXX
    and     rdi, r12
    cmp     rdi, r12
    je      proc0_yes

    cmp     bl, [r10 + 4]              ; diagnol top left to bottom right
    jne     SHORT proc0_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc0_no:
    ret

  proc0_yes:
    mov     rax, rbx
    ret
proc0_X ENDP

align 16
proc1_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 010101h               ; top row XXX
    and     rdi, r12
    cmp     rdi, r12
    je      proc1_yes

    mov     rdi, rsi
    mov     r12, 0100000100000100h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc1_yes:
    mov     rax, rbx
    ret
proc1_X ENDP

align 16
proc2_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 010101h               ; top row XXX
    and     rdi, r12
    cmp     rdi, r12
    je      proc2_yes

    mov     rdi, rsi
    mov     r12, 01000100010000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc2_yes

    cmp     bl, [r10 + 5]              ; right column
    jne     SHORT proc2_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc2_no:
    ret

  proc2_yes:
    mov     rax, rbx
    ret
proc2_X ENDP

align 16
proc3_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 01000001000001h       ; left column
    and     rdi, r12
    cmp     rdi, r12
    je      proc3_yes

    mov     rdi, rsi
    mov     r12, 010101000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc3_yes:
    mov     rax, rbx
    ret
proc3_X ENDP

align 16
proc4_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 010101000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    mov     rdi, rsi
    mov     r12, 01000100010000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    mov     rdi, rsi
    mov     r12, 0100000100000100h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    je      proc4_yes

    cmp     bl, [r10 + 0]              ; diagonal top left to bottom right
    jne     SHORT proc4_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc4_no:
    ret

  proc4_yes:
    mov     rax, rbx
    ret
proc4_X ENDP

align 16
proc5_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 010101000000h         ; middle row
    and     rdi, r12
    cmp     rdi, r12
    je      proc5_yes

    cmp     bl, [r10 + 2]              ; right column
    jne     SHORT proc5_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc5_no:
    ret

  proc5_yes:
    mov     rax, rbx
    ret
proc5_X ENDP

align 16
proc6_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 01000001000001h       ; left column
    and     rdi, r12
    cmp     rdi, r12
    je      proc6_yes

    mov     rdi, rsi
    mov     r12, 01000100010000h       ; diagonal top right to bottom left
    and     rdi, r12
    cmp     rdi, r12
    je      proc6_yes

    cmp     bl, [r10 + 7]              ; bottom row
    jne     SHORT proc6_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc6_no:
    ret

  proc6_yes:
    mov     rax, rbx
    ret
proc6_X ENDP

align 16
proc7_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    mov     r12, 0100000100000100h     ; middle column
    and     rdi, r12
    cmp     rdi, r12
    je      proc7_yes

    cmp     bl, [r10 + 6]              ; bottom row
    jne     SHORT proc7_no
    cmp     bl, [r10 + 8]
    cmove   rax, rbx

  proc7_no:
    ret

  proc7_yes:
    mov     rax, rbx
    ret
proc7_X ENDP

align 16
proc8_X PROC
    mov     rdi, [r10]                 ; rdi should have the first 8 bytes of the board
    mov     rsi, rdi                   ; saved for later
    ; for 8, ignore the byte beyond the qword because we know its value

    mov     r12, 010000010000h         ; right column
    and     rdi, r12
    cmp     rdi, r12
    je      proc8_yes

    mov     rdi, rsi
    mov     r12, 0100000001h           ; diagonal top left to bottom right
    and     rdi, r12
    cmp     rdi, r12
    je      proc8_yes

    mov     rdi, rsi
    mov     r12, 0101000000000000h     ; bottom row
    and     rdi, r12
    cmp     rdi, r12
    cmove   rax, rbx
    ret

  proc8_yes:
    mov     rax, rbx
    ret
proc8_X ENDP

code_ttt ENDS
END

