; build on a Microsoft ARM device like this:
;    armasm64 -nologo ttt_arm64.asm -o ttt_arm64.obj -g
;    link ttt_arm64.obj /nologo /defaultlib:libucrt.lib /defaultlib:libcmt.lib /defaultlib:kernel32.lib ^
;        /defaultlib:legacy_stdio_definitions.lib /entry:mainCRTStartup /subsystem:console
;
; differences from the M1/Apple version:
;     - printf varargs argument passing is different
;     - Win32 CreateThread vs. posix pthread API
;     - loading 64 bit constants and variable labels is different
;     - directives for data/code segments, labels, proc start and end, data statements, equ statements, alignment fill semantics.
;

  IMPORT |printf|
  IMPORT |CreateThread|
  IMPORT |WaitForSingleObject|
  IMPORT |CloseHandle|
  IMPORT |SetProcessAffinityMask|
  IMPORT |GetCurrentProcess|
  EXPORT |main|

iterations    equ 100000
minimum_score equ 2
maximum_score equ 9
win_score     equ 6
lose_score    equ 4
tie_score     equ 5
x_piece       equ 1
o_piece       equ 2
blank_piece   equ 0                     ; not referenced in the code below, but it is assumed to be 0

    AREA |.data|, DATA, align=6, codealign
  ; allocate separate boards for the 3 unique starting moves so multiple threads can solve in parallel
  ; cache lines are 64 bytes, so put each on separate cache lines
  align 64
board0 dcb 1,0,0,0,0,0,0,0,0
  align 64 
board1 dcb 0,1,0,0,0,0,0,0,0
  align 64
board4 dcb 0,0,0,0,1,0,0,0,0

  align 64
priorTicks        dcq 0
moveCount         dcq 0
elapString        dcb "%lld microseconds (-6)\n", 0
itersString       dcb "%d iterations\n", 0
movecountString   dcb "%d moves\n", 0

  area |.code|, code, align=4, codealign
  align 16 
main PROC; linking with the C runtime, so main will be invoked
    ; remember the caller's stack frame and return address
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    ; set which cores the code will run on (optionally)
;    bl       GetCurrentProcess
;    mov      x1, 0x70                   ; on the sq3, 0x7 are the slow 4 cores (efficiency) and 0x70 are the fast 4 cores (performance)
;    bl       SetProcessAffinityMask

    ; remember the starting tickcount
    adrp     x1, priorTicks
    add      x1, x1, priorTicks
    mrs      x0, cntvct_el0
    str      x0, [x1]

    ; generate the 3 solutions in serial
    mov      x0, 0
    bl       _runmm
    mov      x0, 1
    bl       _runmm 
    mov      x0, 4
    bl       _runmm 
 
    bl       _print_elapsed_time        ; show how long it took in serial
    bl       _print_movecount           ; show # of moves, a multiple of 6493
    bl       _solve_threaded            ; now do it in parallel
    bl       _print_elapsed_time        ; show how long it took in parallel
    bl       _print_movecount           ; show # of moves, a multiple of 6493

    ldr      x1, =iterations
    adrp     x0, itersString
    add      x0, x0, itersString
    bl       printf

    mov      x0, 0
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret
    ENDP

  align 16
_print_elapsed_time PROC
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    mrs      x1, cntvct_el0             ; current tick time in x1
    adrp     x3, priorTicks             ; load prior tick count
    add      x3, x3, priorTicks
    ldr      x0, [x3]
    str      x1, [x3]                   ; update prior with current time
    sub      x1, x1, x0
    ldr      x4, =0xf4240               ; 1,000,000 (microseconds)
    mul      x1, x1, x4                 ; save precision by multiplying by a big number
    mrs      x2, cntfrq_el0             ; get the divisor and divide
    udiv     x1, x1, x2
    adrp     x0, elapString
    add      x0, x0, elapString
    bl       printf                     ; print the elapsed time
    
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret
    ENDP

  align 16
_print_movecount PROC
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    adrp     x0, moveCount
    add      x0, x0, moveCount
    ldr      w1, [x0]
    str      xzr, [x0]                    ; reset moveCount to 0   
    adrp     x0, movecountString
    add      x0, x0, movecountString
    bl       printf

    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret
    ENDP

  align 16
_runmm PROC
    ; save all of these because they are all used

    stp      x26, x25, [sp, #-96]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]        
    stp      x22, x21, [sp, #48]
    stp      x20, x19, [sp, #64]       
    stp      x29, x30, [sp, #80]       
    add      x29, sp, #80               

    mov      x19, 0                              ; x19 is the move count
    mov      x23, x0                             ; x23 is the initial move    
    adrp     x20, _winner_functions              ; x20 holds the function table
    add      x20, x20, _winner_functions

    ; load x21 with the board to use
    cmp      x0, 0
    b.ne     _runmm_try1
    adrp     x21, board0
    add      x21, x21, board0
    b        _runmm_for

_runmm_try1
    cmp      x0, 1
    b.ne     _runmm_try4
    adrp     x21, board1
    add      x21, x21, board1
    b        _runmm_for

_runmm_try4
    ; force the move to be 4 at this point
    mov      x0, 4
    mov      x23, 4
    adrp     x21, board4
    add      x21, x21, board4

_runmm_for
    ldr      x22, =iterations           ; x22 is the iteration for loop counter. ldr not mov because it's large

_runmm_loop
    mov      x0, minimum_score          ; alpha
    mov      x1, maximum_score          ; beta
    mov      x2, 0                      ; depth
    mov      x3, x23                    ; move (0..8)
    bl       _minmax_min
    sub      x22, x22, 1
    cmp      x22, 0
    b.ne     _runmm_loop

    ; add the number of moves (atomic because multiple threads may do this at once)
    adrp     x0, moveCount
    add      x0, x0, moveCount
    ldaddal  w19, w19, [x0]

    ; exit the function
    ldp      x29, x30, [sp, #80]
    ldp      x20, x19, [sp, #64]         
    ldp      x22, x21, [sp, #48]        
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #96        
    ret
    ENDP

  align 16
_solve_threaded PROC
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    ; board1 takes the longest to complete; start it first
    mov       x0, 0                 ; no security attributes
    mov       x1, 0                 ; default stack size
    adrp      x2, _runmm
    add       x2, x2, _runmm
    mov       x3, 1                 ; the board to solve
    mov       x4, 0                 ; 0 creation flags
    mov       x5, 0                 ; no thread id
    bl        CreateThread
    mov       x25, x0               ; save the handle here

    ; then start solving board4
    mov       x0, 0                 ; no security attributes
    mov       x1, 0                 ; default stack size
    adrp      x2, _runmm
    add       x2, x2, _runmm
    mov       x3, 4                 ; the board to solve
    mov       x4, 0                 ; 0 creation flags
    mov       x5, 0                 ; no thread id
    bl        CreateThread
    mov       x26, x0               ; save the handle here

    ; solve board0 on this thread
    mov      x0, 0
    bl       _runmm

    ; wait for board4 to complete
    mov      x0, x26
    mov      x1, -1
    bl       WaitForSingleObject
    mov      x0, x26
    bl       CloseHandle

    ; wait for board1 to complete
    mov      x0, x25
    mov      x1, -1
    bl       WaitForSingleObject
    mov      x0, x25
    bl       CloseHandle

    ; exit the function
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret
    ENDP

  align 16
_minmax_max PROC
    ; x0: alpha. keep in register x23
    ; x1: beta. keep in register x24
    ; x2: depth. keep in register x25
    ; x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    ; x19: global move count for this thread
    ; x20: winner function table
    ; x21: the board for this thread
    ; x22: global iteration count
    ; x23: alpha
    ; x24: beta
    ; x25: depth
    ; x26: value: local variable
    ; x27: for loop local variable I
    ; x28: unused

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]         
    stp      x29, x30, [sp, #48]        
    add      x29, sp, #48               

    mov      x23, x0                    ; alpha
    mov      x24, x1                    ; beta
    mov      x25, x2                    ; depth
    add      x19, x19, 1                ; increment global move count

    cmp      x25, 3                     ; if fewer that 5 moves played, no winner
    b.le     _minmax_max_skip_winner

    ; call the winner function for the most recent move
    mov      x0, o_piece                ; the piece just played
    lsl      x3, x3, 3                  ; each function pointer takes 8 bytes (move is trashed)
    add      x3, x20, x3                ; table + function offset
    ldr      x3, [x3]                   ; grab the function pointer
    blr      x3                         ; call it

    cmp      w0, o_piece                ; did O win?
    mov      w0, lose_score             ; move regardless of whether we'll branch
    b.eq     _minmax_max_done

_minmax_max_skip_winner
    mov      w26, minimum_score         ; the value is minimum because we're maximizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

_minmax_max_top_of_loop
    cmp      x27, 8                     ; check before the increment
    b.eq     _minmax_max_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, wzr                    ; is the space free? assumes blank_piece is 0
    b.ne     _minmax_max_top_of_loop

    mov      w2, x_piece                ; make the move
    strb     w2, [x1]

    mov      x0, x23                    ; alpha
    mov      x1, x24                    ; beta
    add      x2, x25, 1                 ; depth++
    mov      x3, x27                    ; move
    bl       _minmax_min                ; recurse to the MIN

    add      x6, x21, x27               ; address of the board + move
    strb     wzr, [x6]                  ; store blank on the board. blank_piece is 0.

    cmp      w0, win_score              ; winning score? 
    b.eq     _minmax_max_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, gt           ; update value if score is > value

    cmp      w23, w26                   ; compare alpha with value
    csel     w23, w26, w23, lt          ; update alpha if alpha is < value

    cmp      w23, w24                   ; compare alpha with beta
    b.ge     _minmax_max_loadv_done     ; alpha pruning if alpha >= beta
 
    b        _minmax_max_top_of_loop    ; loop to the next board position 0..8

_minmax_max_loadv_done
    mov      x0, x26                    ; load the return value with value
  
_minmax_max_done
    ldp      x29, x30, [sp, #48]         
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #64        
    ret
    ENDP

  align 16
_minmax_min PROC
    ; x0: alpha. keep in register x23
    ; x1: beta. keep in register x24
    ; x2: depth. keep in register x25
    ; x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    ; x19: global move count for this thread
    ; x20: winner function table
    ; x21: the board for this thread
    ; x22: global iteration count
    ; x23: alpha
    ; x24: beta
    ; x25: depth
    ; x26: value: local variable
    ; x27: for loop local variable I
    ; x28: unused

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]        
    stp      x29, x30, [sp, #48]       
    add      x29, sp, #48               

    mov      x23, x0                    ; alpha
    mov      x24, x1                    ; beta
    mov      x25, x2                    ; depth
    add      x19, x19, 1                ; update global move count

    cmp      x25, 3                     ; can't be a winner if < 5 moves
    b.le     _minmax_min_skip_winner

    ; call the winner function for the most recent move
    mov      x0, x_piece                ; the piece just played
    lsl      x3, x3, 3                  ; each function pointer takes 8 bytes (move is trashed)
    add      x3, x20, x3                ; table + function offset
    ldr      x3, [x3]                   ; grab the function pointer
    blr      x3                         ; call it

    cmp      w0, x_piece                ; did X win?
    mov      w0, win_score              ; move this regardless of the result
    b.eq     _minmax_min_done

    cmp      x25, 8                     ; recursion can only go 8 deep
    mov      x0, tie_score
    b.eq     _minmax_min_done

_minmax_min_skip_winner
    mov      w26, maximum_score         ; the value is maximum because we're minimizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

_minmax_min_top_of_loop
    cmp      x27, 8                     ; check before the increment
    b.eq     _minmax_min_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27               ; board + move is the address of the piece
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, wzr                    ; is the space free? assumes blank_piece is 0
    b.ne     _minmax_min_top_of_loop

    mov      w2, o_piece                ; the move is O
    strb     w2, [x1]                   ; store the move on the board

    mov      x0, x23                    ; alpha
    mov      x1, x24                    ; beta
    add      x2, x25, 1                 ; depth + 1
    mov      x3, x27                    ; move
    bl       _minmax_max                ; recurse to the MAX

    add      x6, x21, x27               ; address of the board + move
    strb     wzr, [x6]                  ; store blank on the board. blank_piece is 0.

    cmp      w0, lose_score             ; losing score? 
    b.eq     _minmax_min_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, lt           ; update value if score is < value

    cmp      w26, w24                   ; compare value with beta
    csel     w24, w26, w24, lt          ; update beta if value < beta

    cmp      w24, w23                   ; compare beta with alpha
    b.le     _minmax_min_loadv_done     ; beta pruning if beta <= alpha
 
    b        _minmax_min_top_of_loop    ; loop to the next board position 0..8

_minmax_min_loadv_done
    mov      x0, x26                    ; load the return value with value
  
_minmax_min_done
    ldp      x29, x30, [sp, #48]        
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #64        
    ret
    ENDP

  align 16
_pos0func PROC
        ldrb     w9, [x21, #1]
        cmp      w0, w9
        b.ne     LBB0_2
        ldrb     w9, [x21, #2]
        cmp      w0, w9
        b.eq     LBB0_7
LBB0_2
        ldrb     w9, [x21, #3]
        cmp      w0, w9
        b.ne     LBB0_4
        ldrb     w9, [x21, #6]
        cmp      w0, w9
        b.eq     LBB0_7
LBB0_4
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.ne     LBB0_6
        ldrb     w8, [x21, #8]
        cmp      w0, w8
        b.eq     LBB0_7
LBB0_6
        mov      w0, wzr
LBB0_7
        ret
        ENDP

  align 16
_pos1func PROC
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB1_2
        ldrb     w9, [x21, #2]
        cmp      w0, w9
        b.eq     LBB1_5
LBB1_2
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.ne     LBB1_4
        ldrb     w8, [x21, #7]
        cmp      w0, w8
        b.eq     LBB1_5
LBB1_4
        mov      w0, wzr
LBB1_5
        ret
        ENDP
                     
  align 16
_pos2func PROC
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB2_2
        ldrb     w9, [x21, #1]
        cmp      w0, w9
        b.eq     LBB2_7
LBB2_2
        ldrb     w9, [x21, #5]
        cmp          w0, w9
        b.ne     LBB2_4
        ldrb     w9, [x21, #8]
        cmp      w0, w9
        b.eq     LBB2_7
LBB2_4
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.ne     LBB2_6
        ldrb     w8, [x21, #6]
        cmp      w0, w8
        b.eq     LBB2_7
LBB2_6
        mov      w0, wzr
LBB2_7
        ret
        ENDP
                     
  align 16
_pos3func PROC
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.ne     LBB3_2
        ldrb     w9, [x21, #5]
        cmp      w0, w9
        b.eq     LBB3_5
LBB3_2
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB3_4
        ldrb     w8, [x21, #6]
        cmp      w0, w8
        b.eq     LBB3_5
LBB3_4
        mov      w0, wzr
LBB3_5
        ret
        ENDP

  align 16
_pos4func PROC
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB4_2
        ldrb     w9, [x21, #8]
        cmp      w0, w9
        b.eq     LBB4_9
LBB4_2
        ldrb     w9, [x21, #2]
        cmp          w0, w9
        b.ne     LBB4_4
        ldrb     w9, [x21, #6]
        cmp      w0, w9
        b.eq     LBB4_9
LBB4_4
        ldrb     w9, [x21, #1]
        cmp      w0, w9
        b.ne     LBB4_6
        ldrb     w9, [x21, #7]
        cmp      w0, w9
        b.eq     LBB4_9
LBB4_6
        ldrb     w9, [x21, #3]
        cmp      w0, w9
        b.ne     LBB4_8
        ldrb     w8, [x21, #5]
        cmp      w0, w8
        b.eq     LBB4_9
LBB4_8
        mov      w0, wzr
LBB4_9
        ret
        ENDP

  align 16
_pos5func PROC
        ldrb     w9, [x21, #3]
        cmp      w0, w9
        b.ne     LBB5_2
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.eq     LBB5_5
LBB5_2
        ldrb     w9, [x21, #2]
        cmp      w0, w9
        b.ne     LBB5_4
        ldrb     w8, [x21, #8]
        cmp      w0, w8
        b.eq     LBB5_5
LBB5_4
        mov      w0, wzr
LBB5_5
        ret
        ENDP

  align 16
_pos6func PROC
        ldrb     w9, [x21, #7]
        cmp      w0, w9
        b.ne     LBB6_2
        ldrb     w9, [x21, #8]
        cmp      w0, w9
        b.eq     LBB6_7
LBB6_2
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB6_4
        ldrb     w9, [x21, #3]
        cmp      w0, w9
        b.eq     LBB6_7
LBB6_4
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.ne     LBB6_6
        ldrb     w8, [x21, #2]
        cmp      w0, w8
        b.eq     LBB6_7
LBB6_6
        mov      w0, wzr
LBB6_7
        ret
        ENDP
                  
  align 16
_pos7func PROC
        ldrb     w9, [x21, #6]
        cmp      w0, w9
        b.ne     LBB7_2
        ldrb     w9, [x21, #8]
        cmp      w0, w9
        b.eq     LBB7_5
LBB7_2
        ldrb     w9, [x21, #1]
        cmp      w0, w9
        b.ne     LBB7_4
        ldrb     w9, [x21, #4]
        cmp      w0, w9
        b.eq     LBB7_5
LBB7_4
        mov      w0, wzr
LBB7_5
        ret
        ENDP

  align 16
_pos8func PROC
        ldrb     w9, [x21, #6]
        cmp      w0, w9
        b.ne     LBB8_2
        ldrb     w9, [x21, #7]
        cmp      w0, w9
        b.eq     LBB8_7
LBB8_2
        ldrb     w9, [x21, #2]
        cmp      w0, w9
        b.ne     LBB8_4
        ldrb     w9, [x21, #5]
        cmp      w0, w9
        b.eq     LBB8_7
LBB8_4
        ldrb     w9, [x21]
        cmp      w0, w9
        b.ne     LBB8_6
        ldrb     w8, [x21, #4]
        cmp      w0, w8
        b.eq     LBB8_7
LBB8_6
        mov      w0, wzr
LBB8_7
        ret
        ENDP

  AREA |.data|, DATA
  align 16
_winner_functions
    dcq _pos0func
    dcq _pos1func
    dcq _pos2func
    dcq _pos3func
    dcq _pos4func
    dcq _pos5func
    dcq _pos6func
    dcq _pos7func
    dcq _pos8func

    END
