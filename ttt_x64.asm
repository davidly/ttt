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
; use 'and' instruction in scoring procs: .0129
;
; Board: 0 | 1 | 2
;        ---------
;        3 | 4 | 5
;        ---------
;        6 | 7 | 8
;
; Only first moves 0, 1, and 4 are solved since other first moves are reflections
;
; The app takes two optional arguments:
;    - the number of iterations to run. Default is defaultIterations.
;    - the hex affinity mask to select which cores to run on. Default is up to the OS
;    - e.g.: tttx64 10000 0x3

extern printf: PROC
extern _atoi64: PROC
extern _strtoui64: PROC
extern exit: PROC
extern QueryPerformanceCounter: PROC
extern QueryPerformanceFrequency: PROC
extern CreateThread: PROC
extern ResumeThread: PROC
extern WaitForSingleObject: PROC
extern WaitForMultipleObjects: PROC
extern CloseHandle: PROC
extern GetCurrentProcess: PROC
extern SetProcessAffinityMask: PROC
extern GetLastError: PROC

defaultIterations   equ 100000
defaultAffinityMask equ 0              ; use all available cores
minimum_score       equ 2
maximum_score       equ 9
win_score           equ 6
lose_score          equ 4
tie_score           equ 5
x_piece             equ 1
o_piece             equ 2
blank_piece         equ 0              ; not referenced in the code below, but it is assumed to be 0
                                         
; local variable offsets [rbp - X] where X = 1 to N where N is the number of QWORDS beyond 4 reserved at entry
; These are for the functions minmax_min and minmax_max
;I_OFFSET            equ 8 * 1          ; i in the for loop 0..8

; spill offsets -- [rbp + X] where X = 2..5  Spill referrs to saving parameters in registers to memory when needed
; these registers can be spilled: rcx, rdx, r8, r9
; Locations 0 (prior rbp) and 1 (return address) are reserved.
; These are for the functions minmax_min and minmax_max
A_SPILL_OFFSET      equ 8 * 2          ; alpha
B_SPILL_OFFSET      equ 8 * 3          ; beta
V_SPILL_OFFSET      equ 8 * 4          ; value
I_SPILL_OFFSET      equ 8 * 5          ; i in the for loop 0..8

data_ttt SEGMENT ALIGN( 4096 ) 'DATA'
    ; It's important to put each of these boards in separate 64-byte cache lines or multi-core performance is terrible
    ; For some Intel CPUs 256 bytes is required, like the i5-2430M, i7-4770K, and i7-5820K
    BOARD0        db     1,0,0,0,0,0,0,0,0
  align 256 ; 64
    BOARD1        db     0,1,0,0,0,0,0,0,0
  align 256 ; 64
    BOARD4        db     0,0,0,0,1,0,0,0,0
  align 256 ;
    WINPROCS      dq     proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8
  align 128
    runTime       db     'runtime in microseconds (-6): %lld', 10, 13, 0
    caption       db     'Hello world!', 0
    fmtStr        db     'Format string int %I64d %I64d %I64d %I64d %I64d %s', 0
    pieceS        db     '%d', 0
    intS          db     '%d ', 0
    moveStr       db     'moves: %lld', 10, 13, 0
    iterStr       db     'iterations: %lld', 10, 13, 0
    CRLF          db     10, 13, 0
    usageStr      db     'usage: %s [iterations] [hexAffinityMask]', 10, 13, 0
    affinityFail  db     'failed to set affinity mask; illegal mask. error %lld', 10, 13, 0
    affinityStr   db     'affinity mask: %#llx', 10, 13, 0
  align 128
    startTime     dq     0
    endTime       dq     0
    perfFrequency dq     0
    moveCount     dq     0
    loopCount     dq     defaultIterations
    affinityMask  dq     defaultAffinityMask
data_ttt ENDS

code_ttt SEGMENT ALIGN( 4096 ) 'CODE'

usage PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    lea     rcx, [usageStr]
    mov     rdx, QWORD PTR [r12]       ; assumes r12 has argv, set in main()
    call    printf

    mov     rax, -1
    call    exit
usage ENDP

parse_args PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    cmp     rcx, 3
    jg      show_usage

    cmp     rcx, 2
    jl      done_parsing_args
    je      get_iterations

    mov     rcx, QWORD PTR [r12 + 16]
    mov     rdx, 0
    mov     r8, 16
    call    _strtoui64
    cmp     rax, 0
    jz      show_usage
    mov     QWORD PTR [affinityMask], rax

  get_iterations:
    mov     rcx, QWORD PTR [r12 + 8]
    call    _atoi64
    mov     QWORD PTR [loopCount], rax
    cmp     rax, 0
    jne     done_parsing_args

  show_usage:
    call    usage

  done_parsing_args:
    leave
    ret
parse_args ENDP

main PROC ; linking with the C runtime, so main will be invoked
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 4

    mov     r12, rdx
    call    parse_args

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

    cmp     QWORD PTR [affinityMask], 0
    je      after_affinity_mask

    mov     rdx, QWORD PTR [affinityMask]
    lea     rcx, affinityStr
    call    printf

    call     GetCurrentProcess
    mov      rcx, rax
    ; 0111h:  performance cores on i7-1280P
    ; 07000h: efficiency cores on i7-1280P
    ; 0111h:  3 random good cores on 5950x
    mov      rdx, QWORD PTR [affinityMask]
    call     SetProcessAffinityMask
    cmp      rax, 0
    jne      after_affinity_mask
    call     GetLastError
    mov      rdx, rax
    lea      rcx, affinityFail
    call     printf
    call     usage

  after_affinity_mask:
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

    lea     rcx, [iterStr]
    mov     rdx, QWORD PTR [loopCount]
    call    printf

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

boardIndex$ = 32                         ; local variable just above child spill locations
align 16
TTTThreadProc PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32 + 8 * 2              ; only 40 needed, but want to keep stacks 16-byte aligned
    
    xor     r13, r13                     ; and r13 to be the move count
    lea     rsi, [WINPROCS]              ; rsi has the win proc function table
    mov     r14, -1                      ; r14 has -1
    mov     r12, 0                       ; r12 has 0
    
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
    mov     r15, QWORD PTR [loopCount]

    align 16
  TTTThreadProc_loop:
    mov     rcx, minimum_score           ; alpha -- minimum score
    mov     rdx, maximum_score           ; beta -- maximum score
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
    mov     rcx, 2                       ; # of handles to wait for
    lea     rdx, aHandles$[rsp]          ; location of the handles
    mov     r8d, 1                       ; wait for all (true)
    mov     r9, -1                       ; wait forever, INFINITE
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
    sub     rsp, 32                         ; 32 by convention to store 4 spill registers in called functions

    ; rcx: alpha. Store in spill location reserved by parent stack
    ; rdx: beta. Store in spill location reserved by parent stack
    ; r8:  depth. keep in the register
    ; r9:  position of last piece added 0..8. Keep in the register because it's used right away
    ;      later, r9 is the i in the for loop 0..8. Spilled.
    ; r10: the board
    ; r11: value. Spilled.
    ; r12: 0 constant
    ; r13: global minmax call count
    ; r14: -1 constant
    ; r15: reserved for global loop of 10000 calls
    ; rsi: pointer to WINPROCS

    inc     r13                             ; r13 is a global variable with the # of calls to minmax_max and minmax_min

    ; NOTE: rcx, r9, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     short minmax_max_skip_winner    ; if too few moves, there can't be a winner yet

    ; the win procs expect the board in r10
    mov     rax, o_piece                    ; rax contains the player with the latest move on input
    call    QWORD PTR [rsi + r9 * 8]        ; call the proc that checks for wins starting with last piece added

    cmp     rax, o_piece                    ; did O win?
    mov     rax, lose_score                 ; wasted mov if not equal, but it often saves a jump. no cmov for loading register with constant
    je      minmax_max_done

    align   16
  minmax_max_skip_winner:
    mov     [rbp + A_SPILL_OFFSET], rcx     ; alpha saved in the spill location
    mov     [rbp + V_SPILL_OFFSET], r11     ; save value
    mov     [rbp + I_SPILL_OFFSET], r9      ; save i -- the for loop variable
    mov     r11, minimum_score              ; minimum possible score. maximizing, so find a score higher than this
    mov     r9, r14                         ; r9 is I in the for loop 0..8. avoid a jump by starting at -1
    inc     r8                              ; next depth 1..8

    align   16
  minmax_max_top_of_loop:
    cmp     r9, 8                           ; 8 because the board is 0..8. check before incrementing
    je      short minmax_max_loadv_done
    inc     r9

    cmp     BYTE PTR [r10 + r9], r12b       ; is the board position free?
    jne     short minmax_max_top_of_loop    ; move to the next spot on the board

    mov     BYTE PTR [r10 + r9], x_piece    ; make the move

    ; unlike win64 calling conventions, no registers are preserved aside from r8 and globals in r10, r12, r13, and r15
    call    minmax_min                      ; score is in rax on return

    mov     BYTE PTR [r10 + r9], r12b       ; Restore the move on the board to 0 from X

    cmp     rax, win_score                  ; compare score with the winning score
    je      short minmax_max_unspill        ; can't do better than winning score when maximizing

    cmp     rax, r11                        ; compare score with value
    jle     short minmax_max_top_of_loop

    cmp     rax, rdx                        ; compare value with beta
    jge     short minmax_max_unspill        ; beta pruning

    mov     r11, rax                        ; update value with score
    cmp     rax, rcx                        ; compare value with alpha
    cmovg   rcx, rax                        ; update alpha with value
    jmp     short minmax_max_top_of_loop

    align   16
  minmax_max_loadv_done:
    mov     rax, r11                        ; load V then return

    align   16
  minmax_max_unspill:
    dec     r8                              ; restore depth to the current level
    mov     rcx, [rbp + A_SPILL_OFFSET]     ; restore alpha
    mov     r11, [rbp + V_SPILL_OFFSET]     ; restore value
    mov     r9, [rbp + I_SPILL_OFFSET]      ; restore i
  minmax_max_done:
    leave
    ret
minmax_max ENDP

; Even depth = mininize for X in subsequent moves, X just took a move in r9
align 16
minmax_min PROC
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32                         ; 32 by convention to store 4 spill registers in called functions

    ; rcx: alpha. Store in spill location reserved by parent stack
    ; rdx: beta. Store in spill location reserved by parent stack
    ; r8:  depth. keep in the register
    ; r9:  position of last piece added 0..8. Keep in the register because it's used right away
    ;      later, r9 is the i in the for loop 0..8
    ; r10: the board
    ; r11: value
    ; r12: 0 constant
    ; r13: global minmax call count
    ; r14: -1 constant
    ; r15: reserved for global loop of 10000 calls
    ; rsi: pointer to WINPROCS

    inc     r13                             ; r13 is a global variable with the # of calls to minmax_max and minmax_min

    ; NOTE: rcx, r9, and rdx aren't saved in spill locations until actually needed. Don't trash them until after skip_winner

    cmp     r8, 3                           ; # of pieces on board is 1 + depth. So >= 4 means at least 5 moves played
    jle     short minmax_min_skip_winner    ; if too few moves, there can't be a winner yet

    ; the win procs expect the board in r10
    mov     rax, x_piece                    ; rax contains the player with the latest move on input
    call    QWORD PTR [rsi + r9 * 8]        ; call the proc that checks for wins starting with last piece added

    cmp     rax, x_piece                    ; did X win? 
    mov     rax, win_score                  ; wasted mov, but it often saves a jump. no cmov for loading constant to register
    je      minmax_min_done

    cmp     r8, 8                           ; recursion can only go 8 deep before the board is full
    mov     rax, tie_score                  ; wasted mov, but it often saves a jump
    je      minmax_min_done

    align   16
  minmax_min_skip_winner:
    mov     [rbp + B_SPILL_OFFSET], rdx     ; beta saved in the spill location
    mov     [rbp + V_SPILL_OFFSET], r11     ; save value
    mov     [rbp + I_SPILL_OFFSET], r9      ; save i -- the for loop variable
    mov     r11, maximum_score              ; maximum possible score; minimizing, so find a score lower than this 
    mov     r9, r14                         ; r9 is I in the for loop 0..8. avoid a jump by starting at -1
    inc     r8                              ; next depth 1..8

    align   16
  minmax_min_top_of_loop:
    cmp     r9, 8                           ; 8 because the board is 0..8. check before incrementing
    je      short minmax_min_loadv_done
    inc     r9

    cmp     BYTE PTR [r10 + r9], r12b       ; is the board position free?
    jne     short minmax_min_top_of_loop    ; move to the next spot on the board

    mov     BYTE PTR [r10 + r9], o_piece    ; make the move

    ; unlike win64 calling conventions, no registers are preserved aside from r8 and globals in r10, r12, r13, and r15
    call    minmax_max                      ; score is in rax on return

    mov     BYTE PTR [r10 + r9], r12b       ; Restore the move on the board to 0 from O

    cmp     rax, lose_score
    je      short minmax_min_unspill        ; can't do better than losing score when minimizing

    cmp     rax, r11                        ; compare score with value
    jge     short minmax_min_top_of_loop

    cmp     rax, rcx                        ; compare value with alpha
    jle     short minmax_min_unspill        ; alpha pruning

    mov     r11, rax                        ; update value with score
    cmp     rax, rdx                        ; compare value with beta
    cmovl   rdx, rax                        ; update beta with value
    jmp     short minmax_min_top_of_loop    ; loop for the next i

    align   16
  minmax_min_loadv_done:
    mov     rax, r11                        ; load V then return

  minmax_min_unspill:
    dec     r8                              ; restore depth to the current level
    mov     rdx, [rbp + B_SPILL_OFFSET]     ; restore beta
    mov     r11, [rbp + V_SPILL_OFFSET]     ; restore value
    mov     r9, [rbp + I_SPILL_OFFSET]      ; restore i
  minmax_min_done:
    leave
    ret
minmax_min ENDP

align 16
proc0 PROC
    mov     bl, al
    and     al, [r10 + 1]
    and     al, [r10 + 2]
    jnz     short proc0_yes

    mov     al, bl
    and     al, [r10 + 3]
    and     al, [r10 + 6]
    jnz     short proc0_yes

    mov     al, bl
    and     al, [r10 + 4]
    and     al, [r10 + 8]

  proc0_yes:
    ret
proc0 ENDP

align 16
proc1 PROC
    mov     bl, al
    and     al, [r10 + 0]
    and     al, [r10 + 2]
    jnz     short proc1_yes

    mov     al, bl
    and     al, [r10 + 4]
    and     al, [r10 + 7]

  proc1_yes:
    ret
proc1 ENDP

align 16
proc2 PROC
    mov     bl, al
    and     al, [r10 + 0]
    and     al, [r10 + 1]
    jnz     short proc2_yes

    mov     al, bl
    and     al, [r10 + 5]
    and     al, [r10 + 8]
    jnz     short proc2_yes

    mov     al, bl
    and     al, [r10 + 4]
    and     al, [r10 + 6]

  proc2_yes:
    ret
proc2 ENDP

align 16
proc3 PROC
    mov     bl, al
    and     al, [r10 + 0]
    and     al, [r10 + 6]
    jnz     short proc3_yes

    mov     al, bl
    and     al, [r10 + 4]
    and     al, [r10 + 5]

  proc3_yes:
    ret
proc3 ENDP

align 16
proc4 PROC
    mov     bl, al
    and     al, [r10 + 0]
    and     al, [r10 + 8]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [r10 + 2]
    and     al, [r10 + 6]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [r10 + 1]
    and     al, [r10 + 7]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [r10 + 3]
    and     al, [r10 + 5]

  proc4_yes:
    ret
proc4 ENDP

align 16
proc5 PROC
    mov     bl, al
    and     al, [r10 + 3]
    and     al, [r10 + 4]
    jnz     short proc5_yes

    mov     al, bl
    and     al, [r10 + 2]
    and     al, [r10 + 8]

  proc5_yes:
    ret
proc5 ENDP

align 16
proc6 PROC
    mov     bl, al
    and     al, [r10 + 4]
    and     al, [r10 + 2]
    jnz     short proc6_yes

    mov     al, bl
    and     al, [r10 + 0]
    and     al, [r10 + 3]
    jnz     short proc6_yes

    mov     al, bl
    and     al, [r10 + 7]
    and     al, [r10 + 8]

  proc6_yes:
    ret
proc6 ENDP

align 16
proc7 PROC
    mov     bl, al
    and     al, [r10 + 1]
    and     al, [r10 + 4]
    jnz     short proc7_yes

    mov     al, bl
    and     al, [r10 + 6]
    and     al, [r10 + 8]

  proc7_yes:
    ret
proc7 ENDP

align 16
proc8 PROC
    mov     bl, al
    and     al, [r10 + 0]
    and     al, [r10 + 4]
    jnz     short proc8_yes

    mov     al, bl
    and     al, [r10 + 2]
    and     al, [r10 + 5]
    jnz     short proc8_yes

    mov     al, bl
    and     al, [r10 + 6]
    and     al, [r10 + 7]

  proc8_yes:
    ret
proc8 ENDP

code_ttt ENDS
END

