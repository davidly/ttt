;
; Prove that you can't win at tic-tac-toe.
; This code just separates min/max codepaths but doesn't unroll the loops.
; I only tried to optimize for what a C++ compiler could reasonably do with the source code.
; Lots of other optimizations are possible beyond what the compiler could reasonably implement.
;
; Board: 0 | 1 | 2
;        ---------
;        3 | 4 | 5
;        ---------
;        6 | 7 | 8
;
; Only first moves 0, 1, and 4 are solved since other first moves are reflections

iterations       equ     100000         ; # of times to solve the boards
DEBUG            equ     0              ; 1 for debug tracing, 0 otherwise
USE686           equ     0              ; it's actually slower to use the cmov instructions

IF USE686
    .686       ; released by Intel in 1995. First Intel cpu to have cmovX instructions
ELSE
    .386       ; released by Intel in 1985.
ENDIF

.model flat, c

extern QueryPerformanceCounter@4: PROC
extern QueryPerformanceFrequency@4: PROC
extern CreateThread@24: PROC
extern WaitForSingleObject@8: PROC
extern CloseHandle@4: PROC

includelib legacy_stdio_definitions.lib
extern printf: proc

maximum_score    equ     9              ; maximum score
minimum_score    equ     2              ; minimum score
win_score        equ     6              ; winning score
tie_score        equ     5              ; tie score
lose_score       equ     4              ; losing score
x_piece          equ     1              ; X move piece
o_piece          equ     2              ; O move piece
blank_piece      equ     0              ; blank piece

; minmax_x argument offsets [ebp + X] where X = 2 to N DWORDs passed on the stack

ALPHA_OFFSET    equ 4 * 2
BETA_OFFSET     equ 4 * 3

; minmax_x local variable offsets [ebp - X] where X = 1 to N where N is the number of DWORDs

LOCAL_VALUE_OFFSET       equ 4 * 1         ; the value of a board position
LOCAL_I_OFFSET           equ 4 * 2         ; i in the for loop 0..8
LOCAL_NEXT_DEPTH_OFFSET  equ 4 * 3         ; depth at the next level of recursion

data_ttt SEGMENT 'DATA'
    ; It's important to put each of these boards in separate 64-byte cache lines or multi-core performance is 9x slower
    ; Update: make the boards 128 bytes apart since some old Intel CPUs effectively have 128 byte cache lines. 2x faster with this.

    BOARD0        db     1,0,0,0,0,0,0,0,0
    fillbyte0     db     7+48 dup(0)
    fillbyte0b    db     64 dup(0)
    BOARD1        db     0,1,0,0,0,0,0,0,0
    fillbyte1     db     7+48 dup(0)
    fillbyte1b    db     64 dup(0)
    BOARD4        db     0,0,0,0,1,0,0,0,0
    fillbyte4     db     7+48 dup(0)
    fillbyte4b    db     64 dup(0)

    priorTicks    dq     0
    currentTicks  dq     0
    perfFrequency dq     0

    WINPROCS      dd     proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

    moveCount     dd     0
    moveStr       db     'moves: %d', 10, 13, 0

    iterStr       db     'for %d iterations', 10, 13, 0
    elapStr       db     '%d milliseconds', 10, 13, 0

    IF DEBUG
        intS          db     '%d ', 10, 13, 0
        dbg4          db     '%d %d %d %d', 10, 13, 0
    ENDIF
data_ttt ENDS

code_ttt SEGMENT 'CODE'

main PROC ; linking with the C runtime, so main will be invoked
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    push     offset priorTicks
    call     QueryPerformanceCounter@4

    push     offset perfFrequency
    call     QueryPerformanceFrequency@4
    mov      eax, DWORD PTR [perfFrequency]
    mov      ecx, 1000000               ; get it down to milliseconds
    xor      edx, edx
    div      ecx
    mov      DWORD PTR [perfFrequency], eax

    push     0
    call     TTTThreadProc
    push     1
    call     TTTThreadProc
    push     4
    call     TTTThreadProc

    call     show_duration
    call     show_move_count

    call     solve_threaded
    call     show_duration
    call     show_move_count

    push     iterations
    push     offset iterStr
    call     printf
    add      esp, 8

    xor      eax, eax
    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret      8
main ENDP

show_duration PROC
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    push     offset currentTicks
    call     QueryPerformanceCounter@4

    mov      eax, DWORD PTR [currentTicks]
    mov      edx, DWORD PTR [currentTicks + 4]
    mov      ebx, DWORD PTR [priorTicks]
    mov      ecx, DWORD PTR [priorTicks + 4]
    sub      eax, ebx
    sbb      edx, ecx
    idiv     DWORD PTR [perfFrequency]
    xor      edx, edx
    mov      ecx, 1000
    idiv     ecx

    push     eax
    push     offset elapStr
    call     printf
    add      esp, 8

    push     offset priorTicks
    call     QueryPerformanceCounter@4

    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret
show_duration ENDP

show_move_count PROC
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    push     DWORD PTR [moveCount]
    push     offset moveStr
    call     printf
    add      esp, 8
    mov      DWORD PTR [moveCount], 0

    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret
show_move_count ENDP

solve_threaded PROC
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 2                 ; 2 local variables (the handles)
    push     edi
    push     esi

    push     0                          ; no thread id
    push     0                          ; no creation flags
    push     4                          ; argument to the call: board4
    push     offset TTTThreadProc       ; the function to call
    push     0                          ; default stack size
    push     0                          ; no security attributes
    call     CreateThread@24
    mov      DWORD PTR [ ebp - 4 ], eax ; save the thread handle

    push     0                          ; no thread id
    push     0                          ; no creation flags
    push     1                          ; argument to the call: board1
    push     offset TTTThreadProc       ; the function to call
    push     0                          ; default stack size
    push     0                          ; no security attributes
    call     CreateThread@24
    mov      DWORD PTR [ ebp - 8 ], eax ; save the thread handle

    push     0                          ; solve board0 on this thread
    call     TTTThreadProc

    push     -1                         ; wait infinite
    push     DWORD PTR [ ebp - 8 ]
    call     WaitForSingleObject@8
    push     DWORD PTR [ ebp - 8 ]
    call     CloseHandle@4

    push     -1                         ; wait infinite
    push     DWORD PTR [ ebp - 4 ]
    call     WaitForSingleObject@8
    push     DWORD PTR [ ebp - 4 ]
    call     CloseHandle@4

    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret
solve_threaded ENDP

align 4
TTTThreadProc PROC
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 2                 ; 1 local variable
    push     edi
    push     esi

    ; put the board pointer in edi, which becomes a thread-global variable

    mov      eax, [ ebp + 8 ]
    cmp      eax, 0
    jne      TTTThreadProc_try1
    lea      edi, board0
    jmp      TTTThreadProc_for

  TTTThreadProc_try1:
    cmp      eax, 1
    jne      TTTThreadProc_try4
    lea      edi, board1
    jmp      TTTThreadProc_for

  TTTThreadProc_try4:
    mov      eax, 4
    lea      edi, board4

  TTTThreadProc_for:
    mov      DWORD PTR [ebp - 8 ], eax         ; save the first move position
    mov      DWORD PTR [ebp - 4], iterations   ; save the iterations
    xor      esi, esi                          ; zero the thread-global move count

  TTT_ThreadProc_loop:
    mov      edx, DWORD PTR [ebp - 8]   ; first move position
    xor      ecx, ecx                   ; depth (0)
    push     maximum_score              ; beta
    push     minimum_score              ; alpha
    call     minmax_min                 ; x just moved, so miminimize now

    dec      DWORD PTR [ebp - 4]
    cmp      DWORD PTR [ebp - 4], 0
    jne      SHORT TTT_ThreadProc_loop

    lock     add DWORD PTR [moveCount], esi

    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret      4
TTTThreadProc ENDP

align 4
minmax_max PROC
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 3                                ; 3 local variables
    ; don't save/restore esi and edi.
    ; registers usage:
    ;     ecx: depth 0..8
    ;     edx: move 0..8
    ;     esi: thread-global move count
    ;     edi: thread-global board pointer

    inc esi

    cmp      ecx, 3                                    ; only look for a winner if enough pieces are played
    jle      SHORT minmax_max_skip_winner

    mov      al, o_piece
    call     DWORD PTR [ winprocs + edx * 4 ]

    cmp      al, o_piece                               ; check if o won and exit early
    mov      eax, lose_score                           ; this mov may be wasted
    je       SHORT minmax_max_done

  minmax_max_skip_winner:
    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], minimum_score
    mov      DWORD PTR [ ebp - LOCAL_I_OFFSET ], -1
    inc      ecx
    mov      DWORD PTR [ ebp - LOCAL_NEXT_DEPTH_OFFSET ], ecx

  minmax_max_top_of_loop:
    inc      DWORD PTR [ ebp - LOCAL_I_OFFSET ]
    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]   ; overwrite the move passed to this function
    cmp      edx, 9                                    ; done iterating all the moves?
    je       SHORT minmax_max_loadv_done

    cmp      BYTE PTR [ edi + edx ], 0                 ; is that move free on the board?
    jne      SHORT minmax_max_top_of_loop

    mov      BYTE PTR [ edi + edx ], x_piece           ; make the move

    ;     edx already has the move
    mov      ecx, DWORD PTR [ ebp - LOCAL_NEXT_DEPTH_OFFSET ]
    push     DWORD PTR [ ebp + BETA_OFFSET ]           ; beta
    push     DWORD PTR [ ebp + ALPHA_OFFSET ]          ; alpha
    call     minmax_min
 
    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]   ; restore the blank piece on the board
    mov      BYTE PTR [ edi + edx ], blank_piece

    cmp      eax, win_score                            ; if we won, exit early
    je       SHORT minmax_max_done

    mov      ebx, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ] ; update value based on the score
    cmp      eax, ebx

    IF USE686
        cmovg    ebx, eax
        mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], ebx
    ELSE
        jle      minmax_max_no_v_update
        mov      ebx, eax
        mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], ebx
        minmax_max_no_v_update:
    ENDIF

    mov      eax, DWORD PTR [ ebp + ALPHA_OFFSET ]
    cmp      eax, ebx

    IF USE686
        cmovl    eax, ebx
    ELSE
        jge      minmax_max_no_alpha_update
        mov      eax, ebx
        minmax_max_no_alpha_update:
    ENDIF

    cmp      eax, DWORD PTR [ ebp + BETA_OFFSET ]      ; compare alpha with beta
    jge      SHORT minmax_max_loadv_done               ; alpha prune
    mov      DWORD PTR [ ebp + ALPHA_OFFSET ], eax     ; this may just update with the same value

    jmp      SHORT minmax_max_top_of_loop

  minmax_max_loadv_done:
    mov      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]

  minmax_max_done:
    mov      esp, ebp
    pop      ebp
    ret      8
minmax_max ENDP

align 4
minmax_min PROC
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 3                                ; 3 local variables
    ; don't save/restore esi and edi.
    ; registers usage:
    ;     ecx: depth 0..8
    ;     edx: move 0..8
    ;     esi: thread-global move count
    ;     edi: thread-global board pointer

    inc esi
    
    cmp      ecx, 3                                    ; only look for a winner if enough pieces are played
    jle      SHORT minmax_min_skip_winner

    mov      al, x_piece
    call     DWORD PTR [ winprocs + edx * 4 ]
    
    cmp      al, x_piece                               ; check if x won and exit early
    mov      eax, win_score                            ; this mov may be wasted
    je       SHORT minmax_min_done

    cmp      ecx, 8                                    ; can we recurse further?
    mov      eax, tie_score                            ; this mov may be wasted
    je       SHORT minmax_min_done

  minmax_min_skip_winner:
    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], maximum_score
    mov      DWORD PTR [ ebp - LOCAL_I_OFFSET ], -1
    inc      ecx
    mov      DWORD PTR [ ebp - LOCAL_NEXT_DEPTH_OFFSET ], ecx

  minmax_min_top_of_loop:
    inc      DWORD PTR [ ebp - LOCAL_I_OFFSET ]
    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]
    cmp      edx, 9
    je       SHORT minmax_min_loadv_done

    cmp      BYTE PTR [ edi + edx ], 0
    jne      SHORT minmax_min_top_of_loop

    mov      BYTE PTR [ edi + edx ], o_piece           ; make the move

    ;    edx already has the move
    mov      ecx, DWORD PTR [ ebp - LOCAL_NEXT_DEPTH_OFFSET ]
    push     DWORD PTR [ ebp + BETA_OFFSET ]           ; beta     
    push     DWORD PTR [ ebp + ALPHA_OFFSET ]          ; alpha    
    call     minmax_max                                           
    
    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]   ; restore the blank piece on the board
    mov      BYTE PTR [ edi + edx ], blank_piece

    cmp      eax, lose_score                           ; if we lost, exit early
    je       SHORT minmax_min_done

    mov      ebx, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]   ; update value based on the score
    cmp      eax, ebx

    IF USE686
        cmovl    ebx, eax
        mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], ebx
    ELSE
        jge      minmax_min_no_v_update
        mov      ebx, eax
        mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], ebx
        minmax_min_no_v_update:
    ENDIF

    mov      eax, DWORD PTR [ ebp + BETA_OFFSET ]
    cmp      eax, ebx

    IF USE686
        cmovg    eax, ebx
    ELSE
        jle      minmax_min_no_beta_update
        mov      eax, ebx
        minmax_min_no_beta_update:
    ENDIF

    cmp      eax, DWORD PTR [ ebp + ALPHA_OFFSET ]     ; compare beta with alpha
    jle      SHORT minmax_min_loadv_done               ; beta prune
    mov      DWORD PTR [ ebp + BETA_OFFSET ], eax      ; this may just update with the same value

    jmp      SHORT minmax_min_top_of_loop

  minmax_min_loadv_done:
    mov      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]

  minmax_min_done:
    mov      esp, ebp
    pop      ebp
    ret      8
minmax_min ENDP

align 4
proc0 PROC
    cmp     al, [edi + 1]
    jne     SHORT proc0_next_win
    cmp     al, [edi + 2]
    je      SHORT proc0_yes

  proc0_next_win:
    cmp     al, [edi + 3]
    jne     SHORT proc0_next_win2
    cmp     al, [edi + 6]
    je      SHORT proc0_yes

  proc0_next_win2:
    cmp     al, [edi + 4]
    jne     SHORT proc0_no
    cmp     al, [edi + 8]
    je      SHORT proc0_yes

  proc0_no:
    xor     eax, eax

  proc0_yes:
    ret
proc0 ENDP

align 4
proc1 PROC
    cmp     al, [edi + 0]
    jne     SHORT proc1_next_win
    cmp     al, [edi + 2]
    je      SHORT proc1_yes

  proc1_next_win:
    cmp     al, [edi + 4]
    jne     SHORT proc1_no
    cmp     al, [edi + 7]
    je      SHORT proc1_yes

  proc1_no:
    xor     eax, eax
    ret

  proc1_yes:
    ret
proc1 ENDP

align 4
proc2 PROC
    cmp     al, [edi + 0]
    jne     SHORT proc2_next_win
    cmp     al, [edi + 1]
    je      SHORT proc2_yes

  proc2_next_win:
    cmp     al, [edi + 5]
    jne     SHORT proc2_next_win2
    cmp     al, [edi + 8]
    je      SHORT proc2_yes

  proc2_next_win2:
    cmp     al, [edi + 4]
    jne     SHORT proc2_no
    cmp     al, [edi + 6]
    je      SHORT proc2_yes

  proc2_no:
    xor      eax, eax
    ret

  proc2_yes:
    ret
proc2 ENDP

align 4
proc3 PROC
    cmp     al, [edi + 0]
    jne     SHORT proc3_next_win
    cmp     al, [edi + 6]
    je      SHORT proc3_yes

  proc3_next_win:
    cmp     al, [edi + 4]
    jne     SHORT proc3_no
    cmp     al, [edi + 5]
    je      SHORT proc3_yes

  proc3_no:
    xor     eax, eax
    ret

  proc3_yes:
    ret
proc3 ENDP

align 4
proc4 PROC
    cmp     al, [edi + 0]
    jne     SHORT proc4_next_win
    cmp     al, [edi + 8]
    je      SHORT proc4_yes

  proc4_next_win:
    cmp     al, [edi + 2]
    jne     SHORT proc4_next_win2
    cmp     al, [edi + 6]
    je      SHORT proc4_yes

  proc4_next_win2:
    cmp     al, [edi + 1]
    jne     SHORT proc4_next_win3
    cmp     al, [edi + 7]
    je      SHORT proc4_yes

  proc4_next_win3:
    cmp     al, [edi + 3]
    jne     SHORT proc4_no
    cmp     al, [edi + 5]
    je      SHORT proc4_yes

  proc4_no:
    xor     eax, eax
    ret

  proc4_yes:
    ret
proc4 ENDP

align 4
proc5 PROC
    cmp     al, [edi + 3]
    jne     SHORT proc5_next_win
    cmp     al, [edi + 4]
    je      SHORT proc5_yes

  proc5_next_win:
    cmp     al, [edi + 2]
    jne     SHORT proc5_no
    cmp     al, [edi + 8]
    je      SHORT proc5_yes

  proc5_no:
    xor      eax, eax
    ret

  proc5_yes:
    ret
proc5 ENDP

align 4
proc6 PROC
    cmp     al, [edi + 4]
    jne     SHORT proc6_next_win
    cmp     al, [edi + 2]
    je      SHORT proc6_yes

  proc6_next_win:
    cmp     al, [edi + 0]
    jne     SHORT proc6_next_win2
    cmp     al, [edi + 3]
    je      SHORT proc6_yes

  proc6_next_win2:
    cmp     al, [edi + 7]
    jne     SHORT proc6_no
    cmp     al, [edi + 8]
    je      SHORT proc6_yes

  proc6_no:
    xor      eax, eax
    ret

  proc6_yes:
    ret
proc6 ENDP

align 4
proc7 PROC
    cmp     al, [edi + 1]
    jne     SHORT proc7_next_win
    cmp     al, [edi + 4]
    je      SHORT proc7_yes

  proc7_next_win:
    cmp     al, [edi + 6]
    jne     SHORT proc7_no
    cmp     al, [edi + 8]
    je      SHORT proc7_yes

  proc7_no:
    xor     eax, eax
    ret

  proc7_yes:
    ret
proc7 ENDP

align 4
proc8 PROC
    cmp     al, [edi + 0]
    jne     SHORT proc8_next_win
    cmp     al, [edi + 4]
    je      SHORT proc8_yes

  proc8_next_win:
    cmp     al, [edi + 2]
    jne     SHORT proc8_next_win2
    cmp     al, [edi + 5]
    je      SHORT proc8_yes

  proc8_next_win2:
    cmp     al, [edi + 6]
    jne     SHORT proc8_no
    cmp     al, [edi + 7]
    je      SHORT proc8_yes

  proc8_no:
    xor      eax, eax
    ret

  proc8_yes:
    ret
proc8 ENDP

; These are needed to link using the old ml.exe and link.exe required to set /subsystem:console,3.10 so binaries can run on Windows XP

__scrt_exe_initialize_mta PROC
    ret
__scrt_exe_initialize_mta ENDP
_filter_x86_sse2_floating_point_exception PROC
    ret
_filter_x86_sse2_floating_point_exception ENDP

code_ttt ENDS
END

