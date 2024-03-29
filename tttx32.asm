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
;
; This prints elapsed time in two ways because Windows 98 and XP produced different results; GetTickCount is more accurate for them
;
; The app takes two optional arguments:
;    - the number of iterations to run. Default is defaultIterations.
;    - the hex affinity mask to select which cores to run on. Default is up to the OS
;    - e.g.: tttx64 10000 0x3
;
; GetTickCount is MUCH more accurate on Win7 and earlier. QueryPerformanceCounter is more accurate on later versions.

defaultIterations   equ    100000         ; # of times to solve the boards
defaultAffinityMask equ    0              ; use all processors by default

IFDEF USE686
    .686                                  ; released by Intel in 1995. First Intel cpu to have cmovX instructions
ELSE
    .386                                  ; released by Intel in 1985.
ENDIF

.model flat, c

extern QueryPerformanceCounter@4: PROC
extern QueryPerformanceFrequency@4: PROC
extern CreateThread@24: PROC
extern WaitForSingleObject@8: PROC
extern CloseHandle@4: PROC
extern GetTickCount@0: PROC
extern GetLastError@0: PROC
extern SetProcessAffinityMask@8: PROC
extern GetProcessAffinityMask@12: PROC
extern GetCurrentProcess@0: PROC

includelib kernel32.lib

extern printf: proc
extern atoi: proc
extern strtoul: proc
extern exit: proc

maximum_score      equ     9              ; maximum score
minimum_score      equ     2              ; minimum score
win_score          equ     6              ; winning score
tie_score          equ     5              ; tie score
lose_score         equ     4              ; losing score
x_piece            equ     1              ; X move piece
o_piece            equ     2              ; O move piece
blank_piece        equ     0              ; blank piece

; minmax_x argument offsets [ebp + X] where X = 2 to 1+N DWORDs passed on the stack

ARG_ALPHA_OFFSET   equ 4 * 2
ARG_BETA_OFFSET    equ 4 * 3

; minmax_x local variable offsets [ebp - X] where X = 1 to N where N is the number of DWORDs

LOCAL_VALUE_OFFSET       equ 4 * 1        ; the value of a board position
LOCAL_I_OFFSET           equ 4 * 2        ; i in the for loop 0..8

data_ttt SEGMENT 'DATA'
    ; It's important to put each of these boards in separate 64-byte cache lines or multi-core performance is 9x slower
    ; Update: make the boards 128 bytes apart since some old Intel CPUs effectively have 128 byte cache lines. 2x faster with this.

    BOARD0         db     1,0,0,0,0,0,0,0,0
    fillbyte0      db     7+48 dup(0)
    fillbyte0b     db     64 dup(0)
    BOARD1         db     0,1,0,0,0,0,0,0,0
    fillbyte1      db     7+48 dup(0)
    fillbyte1b     db     64 dup(0)
    BOARD4         db     0,0,0,0,1,0,0,0,0
    fillbyte4      db     7+48 dup(0)
    fillbyte4b     db     64 dup(0)

    priorTicks     dq     0
    currentTicks   dq     0
    perfFrequency  dq     0

    WINPROCS       dd     proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

    tickCountPrior dd     0
    tickCountNow   dd     0
    threadID       dd     0
    moveCount      dd     0
    loopCount      dd     defaultIterations
    affinityMask   dd     defaultAffinityMask
    processAM      dd     0
    systemAM       dd     0
    moveStr        db     'moves: %u', 10, 13, 0
    tickStr        db     'ticks: %u', 10, 13, 0
    iterStr        db     'for %u iterations', 10, 13, 0
    elapStr        db     '%u milliseconds', 10, 13, 0
    usageStr       db     'usage: %s [iterations] [hexAffinityMask]', 10, 13, 0
    affinityFail   db     'failed to set affinity mask; illegal mask. error %d', 10, 13, 0
    showAMStr      db     'process %#x and system %#x affinity masks', 10, 13, 0
    affinityStr    db     'affinity mask: %#x', 10, 13, 0
data_ttt ENDS

code_ttt SEGMENT 'CODE'

usage PROC
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    push     DWORD PTR [edi]              ; assumes argv is in edi, set by main()
    lea      ecx, [usageStr]
    push     ecx
    call     printf
    add      esp, 8

    push     -1
    call     exit
usage ENDP

parse_args PROC
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    mov      esi, ecx
    cmp      esi, 3
    jg       show_usage

    cmp      esi, 2
    jl       done_parsing_args
    je       get_iterations

    push     16
    push     0
    mov      eax, DWORD PTR [edi + 8]
    push     eax
    call     strtoul
    add      esp, 12
    cmp      eax, 0
    je       show_usage
    mov      DWORD PTR [affinityMask], eax

  get_iterations:
    push     DWORD PTR [edi + 4]
    call     atoi
    add      esp, 4
    mov      DWORD PTR [loopCount], eax
    cmp      eax, 0
    jne      done_parsing_args

  show_usage:
    call     usage

  done_parsing_args:
    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret
parse_args ENDP

main PROC ; linking with the C runtime, so main will be invoked
    push     ebp
    mov      ebp, esp
    push     edi
    push     esi

    mov      ecx, DWORD PTR [ebp + 8]                      ; argc
    mov      edx, DWORD PTR [ebp + 12]                     ; argv
    mov      edi, edx                                      ; save arg for later
    call     parse_args

    cmp      DWORD PTR [affinityMask], 0
    je       after_affinity_mask

    push     DWORD PTR [affinityMask]
    lea      eax, affinityStr
    push     eax
    call     printf
    add      esp, 8

    ;lea      eax, systemAM
    ;push     eax
    ;lea      eax, processAM
    ;push     eax
    ;call     GetCurrentProcess@0
    ;push     eax
    ;call     GetProcessAffinityMask@12
    ;push     DWORD PTR [systemAM]
    ;push     DWORD PTR [processAM]
    ;lea      eax, showAMStr
    ;push     eax
    ;call     printf
    ;add      esp, 12

    ; 0111h:  performance cores on i7-1280P
    ; 07000h: efficiency cores on i7-1280P
    ; 0111h:  3 random good cores on 5950x
    mov      eax, DWORD PTR [affinityMask]
    push     eax
    call     GetCurrentProcess@0
    push     eax
    call     SetProcessAffinityMask@8
    cmp      eax, 0
    jne      after_affinity_mask
    call     GetLastError@0
    push     eax
    lea      eax, affinityFail
    push     eax
    call     printf
    add      esp, 8
    call     usage

  after_affinity_mask:
    push     offset perfFrequency
    call     QueryPerformanceFrequency@4
    mov      eax, DWORD PTR [perfFrequency]
    mov      ecx, 1000000                                  ; get it down to milliseconds
    xor      edx, edx
    div      ecx
    mov      DWORD PTR [perfFrequency], eax

    ; GetTickCount is more accurate by a lot on WinXP and Windows 7. QueryPerformanceCounter is more accurate by a lot elsewhere.
    call     GetTickCount@0
    mov      DWORD PTR [tickCountPrior], eax

    push     offset priorTicks
    call     QueryPerformanceCounter@4

    push     0
    call     TTTThreadProc
    push     1
    call     TTTThreadProc
    push     4
    call     TTTThreadProc

    call     GetTickCount@0
    sub      eax, DWORD PTR [tickCountPrior]
    push     eax
    push     offset tickStr
    call     printf
    add      esp, 8

    call     show_duration
    call     show_move_count

    call     GetTickCount@0
    mov      DWORD PTR [tickCountPrior], eax

    call     solve_threaded

    call     GetTickCount@0
    sub      eax, DWORD PTR [tickCountPrior]
    push     eax
    push     offset tickStr
    call     printf
    add      esp, 8

    call     show_duration
    call     show_move_count

    push     DWORD PTR [loopCount]
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
    sub      esp, 4 * 2                                    ; 2 local variables (the handles)
    push     edi
    push     esi

    push     offset threadID                               ; win9x requires non-0 thread id pointer
    push     0                                             ; no creation flags
    push     4                                             ; argument to the call: board4
    push     offset TTTThreadProc                          ; the function to call
    push     0                                             ; default stack size
    push     0                                             ; no security attributes
    call     CreateThread@24
    mov      DWORD PTR [ ebp - 4 ], eax                    ; save the thread handle

    push     offset threadID                               ; win9x requires non-0 thread id pointer
    push     0                                             ; no creation flags
    push     1                                             ; argument to the call: board1
    push     offset TTTThreadProc                          ; the function to call
    push     0                                             ; default stack size
    push     0                                             ; no security attributes
    call     CreateThread@24
    mov      DWORD PTR [ ebp - 8 ], eax                    ; save the thread handle

    push     0                                             ; solve board0 on this thread
    call     TTTThreadProc

    push     -1                                            ; wait infinite
    push     DWORD PTR [ ebp - 8 ]
    call     WaitForSingleObject@8
    push     DWORD PTR [ ebp - 8 ]
    call     CloseHandle@4

    push     -1                                            ; wait infinite
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
    sub      esp, 4 * 2                                    ; 1 local variable
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
    mov      DWORD PTR [ebp - 8], eax                      ; save the first move position
    mov      eax, DWORD PTR [loopCount]
    mov      DWORD PTR [ebp - 4], eax                      ; save the iterations
    xor      esi, esi                                      ; zero the thread-global move count

  TTT_ThreadProc_loop:
    mov      edx, DWORD PTR [ebp - 8]                      ; first move position
    xor      ecx, ecx                                      ; depth (0)
    push     maximum_score                                 ; beta
    push     minimum_score                                 ; alpha
    call     minmax_min                                    ; x just moved, so miminimize now

    dec      DWORD PTR [ebp - 4]
    jne      short TTT_ThreadProc_loop

    lock     add DWORD PTR [moveCount], esi

    pop      esi
    pop      edi
    mov      esp, ebp
    pop      ebp
    ret      4
TTTThreadProc ENDP

align 4
minmax_max PROC
    ; don't save/restore esi and edi.
    ; registers usage:
    ;     ebx: local scratchpad
    ;     ecx: depth 0..8
    ;     edx: move 0..8
    ;     esi: thread-global move count
    ;     edi: thread-global board pointer
    ; don't setup the stack frame before checking if we can exit early

    inc      esi

    cmp      ecx, 3                                        ; only look for a winner if enough pieces are played
    jle      short minmax_max_skip_winner

    mov      al, o_piece
    call     DWORD PTR [ winprocs + edx * 4 ]

align 4
    cmp      al, o_piece                                   ; check if o won and exit early
    jne      minmax_max_skip_winner
    mov      eax, lose_score                               ; this mov may be wasted
    ret      8

align 4
  minmax_max_skip_winner:
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 2

    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], minimum_score
    mov      edx, -1
    inc      ecx

align 4
  minmax_max_top_of_loop:
    cmp      edx, 8                                        ; done iterating all the moves?
    je       short minmax_max_loadv_done
    inc      edx 

    cmp      BYTE PTR [ edi + edx ], 0                     ; is that move free on the board?
    jne      short minmax_max_top_of_loop
    mov      DWORD PTR [ ebp - LOCAL_I_OFFSET ], edx
    mov      BYTE PTR [ edi + edx ], x_piece               ; make the move

    ; edx already has the move
    push     DWORD PTR [ ebp + ARG_BETA_OFFSET ]           ; beta
    push     DWORD PTR [ ebp + ARG_ALPHA_OFFSET ]          ; alpha
    call     minmax_min

    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]       ; restore the blank piece on the board
    mov      BYTE PTR [ edi + edx ], blank_piece

    cmp      eax, win_score                                ; if we won, exit early
    je       short minmax_max_done

    cmp      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]   ; compare score with value
    jle      short minmax_max_top_of_loop

    cmp      eax, DWORD PTR [ ebp + ARG_BETA_OFFSET ]      ; compare value with beta
    jge      short minmax_max_done

    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], eax   ; update value with score
    lea      ebx, [ ebp + ARG_ALPHA_OFFSET ]               ; save address of alpha
    cmp      eax, [ebx]                                    ; compare value with alpha
    jle      short minmax_max_top_of_loop
    
    mov      [ebx], eax                                    ; update alpha
    jmp      short minmax_max_top_of_loop

align 4
  minmax_max_loadv_done:
    mov      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]

align 4
  minmax_max_done:
    dec      ecx
    mov      esp, ebp
    pop      ebp
    ret      8
minmax_max ENDP

align 4
minmax_min PROC
    ; don't save/restore esi and edi.
    ; registers usage:
    ;     ebx: local scratchpad
    ;     ecx: depth 0..8
    ;     edx: move 0..8
    ;     esi: thread-global move count
    ;     edi: thread-global board pointer
    ; don't setup the stack frame unless we don't exit early

    inc      esi
    
    cmp      ecx, 3                                        ; only look for a winner if enough pieces are played
    jle      short minmax_min_skip_winner

    mov      al, x_piece
    call     DWORD PTR [ winprocs + edx * 4 ]
    
align 4
    cmp      al, x_piece                                   ; check if x won and exit early
    jne      minmax_min_check_tail
    mov      eax, win_score                                ; this mov may be wasted
    ret      8

  minmax_min_check_tail:
    cmp      ecx, 8                                        ; can we recurse further?
    jne      minmax_min_skip_winner
    mov      eax, tie_score                                ; this mov may be wasted
    ret      8

align 4
  minmax_min_skip_winner:
    push     ebp
    mov      ebp, esp
    sub      esp, 4 * 2

    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], maximum_score
    mov      edx, -1
    inc      ecx

align 4
  minmax_min_top_of_loop:
    cmp      edx, 8
    je       short minmax_min_loadv_done
    inc      edx 

    cmp      BYTE PTR [ edi + edx ], 0
    jne      short minmax_min_top_of_loop
    mov      DWORD PTR [ ebp - LOCAL_I_OFFSET ], edx
    mov      BYTE PTR [ edi + edx ], o_piece               ; make the move

    ; edx already has the move
    push     DWORD PTR [ ebp + ARG_BETA_OFFSET ]           ; beta     
    push     DWORD PTR [ ebp + ARG_ALPHA_OFFSET ]          ; alpha    
    call     minmax_max                                           

    mov      edx, DWORD PTR [ ebp - LOCAL_I_OFFSET ]       ; restore the blank piece on the board
    mov      BYTE PTR [ edi + edx ], blank_piece

    cmp      eax, lose_score                               ; if we lost, exit early
    je       short minmax_min_done

    cmp      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]   ; compare score with value
    jge      short minmax_min_top_of_loop

    cmp      eax, DWORD PTR [ ebp + ARG_ALPHA_OFFSET ]     ; compare value with alpha
    jle      short minmax_min_done

    mov      DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ], eax   ; update value with score
    lea      ebx, [ ebp + ARG_BETA_OFFSET ]                ; save address of beta
    cmp      eax, [ebx]                                    ; compare value with beta
    jge      short minmax_min_top_of_loop
    
    mov      [ebx], eax                                    ; update beta
    jmp      short minmax_min_top_of_loop

align 4
  minmax_min_loadv_done:
    mov      eax, DWORD PTR [ ebp - LOCAL_VALUE_OFFSET ]

align 4
  minmax_min_done:
    dec      ecx
    mov      esp, ebp
    pop      ebp
    ret      8
minmax_min ENDP

align 4
proc0 PROC
    mov     bl, al
    and     al, [edi + 1]
    and     al, [edi + 2]
    jnz     short proc0_yes

    mov     al, bl
    and     al, [edi + 3]
    and     al, [edi + 6]
    jnz     short proc0_yes

    mov     al, bl
    and     al, [edi + 4]
    and     al, [edi + 8]

  proc0_yes:
    ret
proc0 ENDP

align 4
proc1 PROC
    mov     bl, al
    and     al, [edi + 0]
    and     al, [edi + 2]
    jnz     short proc1_yes

    mov     al, bl
    and     al, [edi + 4]
    and     al, [edi + 7]

  proc1_yes:
    ret
proc1 ENDP

align 4
proc2 PROC
    mov     bl, al
    and     al, [edi + 0]
    and     al, [edi + 1]
    jnz     short proc2_yes

    mov     al, bl
    and     al, [edi + 5]
    and     al, [edi + 8]
    jnz     short proc2_yes

    mov     al, bl
    and     al, [edi + 4]
    and     al, [edi + 6]

  proc2_yes:
    ret
proc2 ENDP

align 4
proc3 PROC
    mov     bl, al
    and     al, [edi + 0]
    and     al, [edi + 6]
    jnz     short proc3_yes

    mov     al, bl
    and     al, [edi + 4]
    and     al, [edi + 5]

  proc3_yes:
    ret
proc3 ENDP

align 4
proc4 PROC
    mov     bl, al
    and     al, [edi + 0]
    and     al, [edi + 8]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [edi + 2]
    and     al, [edi + 6]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [edi + 1]
    and     al, [edi + 7]
    jnz     short proc4_yes

    mov     al, bl
    and     al, [edi + 3]
    and     al, [edi + 5]

  proc4_yes:
    ret
proc4 ENDP

align 4
proc5 PROC
    mov     bl, al
    and     al, [edi + 3]
    and     al, [edi + 4]
    jnz     short proc5_yes

    mov     al, bl
    and     al, [edi + 2]
    and     al, [edi + 8]

  proc5_yes:
    ret
proc5 ENDP

align 4
proc6 PROC
    mov     bl, al
    and     al, [edi + 4]
    and     al, [edi + 2]
    jnz     short proc6_yes

    mov     al, bl
    and     al, [edi + 0]
    and     al, [edi + 3]
    jnz     short proc6_yes

    mov     al, bl
    and     al, [edi + 7]
    and     al, [edi + 8]

  proc6_yes:
    ret
proc6 ENDP

align 4
proc7 PROC
    mov     bl, al
    and     al, [edi + 1]
    and     al, [edi + 4]
    jnz     short proc7_yes

    mov     al, bl
    and     al, [edi + 6]
    and     al, [edi + 8]

  proc7_yes:
    ret
proc7 ENDP

align 4
proc8 PROC
    mov     bl, al
    and     al, [edi + 0]
    and     al, [edi + 4]
    jnz     short proc8_yes

    mov     al, bl
    and     al, [edi + 2]
    and     al, [edi + 5]
    jnz     short proc8_yes

    mov     al, bl
    and     al, [edi + 6]
    and     al, [edi + 7]

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

