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
;     - setting processor affinity is different; only native OS API are available
;
; The app takes two optional arguments:
;    - the number of iterations to run. Default is defaultIterations.
;    - the hex affinity mask to select which cores to run on. Default is up to the OS
;    - e.g.: ttt_arm64 10000 0x3
;    - on the SQ3, 0xf are the 4 efficiency cores and 0xf0 are the 4 performance cores
;
; Handy reminder: brk      #0xF000



  IMPORT |printf|
  IMPORT |exit|
  IMPORT |_strtoui64|
  IMPORT |CreateThread|
  IMPORT |WaitForSingleObject|
  IMPORT |CloseHandle|
  IMPORT |SetProcessAffinityMask|
  IMPORT |GetCurrentProcess|
  IMPORT |GetLastError|
  EXPORT |main|

defaultIterations   equ 100000
defaultAffinityMask equ 0               ; let the OS use any cores it wants
minimum_score       equ 2
maximum_score       equ 9
win_score           equ 6
lose_score          equ 4
tie_score           equ 5
x_piece             equ 1
o_piece             equ 2
blank_piece         equ 0               ; not referenced in the code below, but it is assumed to be 0

  area |.data|, data, align=6, codealign
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
loopCount         dcq defaultIterations
affinityMask      dcq defaultAffinityMask
elapString        dcb "%lld microseconds (-6)\n", 0
itersString       dcb "%d iterations\n", 0
movecountString   dcb "%d moves\n", 0
usageStr          dcb "usage: %s [iterations] [hexAffinityMask]\n", 0
affinityFail      dcb "failed to set affinity mask; illegal mask. error %lld\n", 0
affinityStr       dcb "affinity mask: %#llx\n", 0

  area |.code|, code, align=4, codealign
  align 16
usage PROC
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    ldr      x1, [x21]
    adrp     x0, usageStr
    add      x0, x0, usageStr
    bl       printf

    mov      x0, -1
    bl       exit
    ENDP

  align 16 
parse_args PROC                         ; assumes x20=argc and x21=argv
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    cmp      x20, 3
    b.gt     show_usage

    cmp      x20, 2
    b.lt     done_parsing_args
    b.eq     get_iterations

    ldr      x0, [x21, #16]
    mov      x1, 0
    mov      x2, 16
    bl       _strtoui64
    cmp      x0, 0
    b.eq     show_usage
    adrp     x1, affinityMask
    add      x1, x1, affinityMask
    str      x0, [x1]

get_iterations
    ldr      x0, [x21, #8]
    mov      x1, 0
    mov      x2, 10
    bl       _strtoui64
    adrp     x1, loopCount
    add      x1, x1, loopCount
    str      x0, [x1]
    cmp      x0, 0
    b.ne     done_parsing_args

show_usage
    bl       usage

done_parsing_args
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret
    ENDP

  align 16 
main PROC; linking with the C runtime, so main will be invoked
    ; remember the caller's stack frame and return address
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    mov      x20, x0                    ; save argc
    mov      x21, x1                    ; save argv
    bl       parse_args                 ; parse optional loop count and affinity mask

    adrp     x1, affinityMask           ; if there is an affinity mask, print it
    add      x1, x1, affinityMask
    ldr      x1, [x1]
    cmp      x1, 0
    b.eq     after_affinity_mask
    mov      x22, x1
    adrp     x0, affinityStr
    add      x0, x0, affinityStr
    bl       printf

    bl       GetCurrentProcess          ; set the affinity mask
    mov      x1, x22
    bl       SetProcessAffinityMask
    cmp      x0, 0
    b.ne     after_affinity_mask

    bl       GetLastError               ; failure -- show the error
    mov      x1, x0
    adrp     x0, affinityFail
    add      x0, x0, affinityFail
    bl       printf
    bl       usage

after_affinity_mask

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

    adrp     x1, loopCount
    add      x1, x1, loopCount
    ldr      x1, [x1]
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

    mov      x27, x0                             ; x27 is the initial move. it's local to this function

    ; x19 and x20 are thread-global
    mov      x19, 0                              ; x19 is the move count
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
    mov      x27, 4
    adrp     x21, board4
    add      x21, x21, board4

_runmm_for
    adrp     x22, loopCount
    add      x22, x22, loopCount
    ldr      x22, [x22]

_runmm_loop
    mov      x23, minimum_score         ; alpha
    mov      x24, maximum_score         ; beta
    mov      x2, 0                      ; depth
    mov      x3, x27                    ; move (0..8)
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
    ; x0: unused (first argument is in x23)
    ; x1: unused (second argument is in x24)
    ; x2: depth. keep in register x25
    ; x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    ; x19: global move count for this thread
    ; x20: winner function table
    ; x21: the board for this thread
    ; x22: global iteration count
    ; x23: alpha (argument)
    ; x24: beta (argument)
    ; x25: next depth
    ; x26: value: local variable
    ; x27: for loop local variable I
    ; x28: the piece to move

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]         
    stp      x29, x30, [sp, #48]        
    add      x29, sp, #48               

    add      x19, x19, 1                ; increment global move count

    cmp      x2, 3                      ; if fewer that 5 moves played, no winner
    b.le     _minmax_max_skip_winner

    ; call the winner function for the most recent move
    mov      x0, o_piece                ; the piece just played
    add      x3, x20, x3, lsl #3        ; calculate the function pointer offset
    ldr      x3, [x3]                   ; grab the function pointer
    blr      x3                         ; call it

    cmp      w0, o_piece                ; did O win?
    mov      w0, lose_score             ; move regardless of whether we'll branch
    b.eq     _minmax_max_done

_minmax_max_skip_winner
    add      x25, x2, 1                 ; next depth
    mov      w28, x_piece               ; making X moves below
    mov      w26, minimum_score         ; the value is minimum because we're maximizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

_minmax_max_top_of_loop
    cmp      x27, 8                     ; check before the increment
    b.eq     _minmax_max_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27               ; save board position in x1 for now and later
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, wzr                    ; is the space free? assumes blank_piece is 0
    b.ne     _minmax_max_top_of_loop

    strb     w28, [x1]                  ; make the move

    ; x23 and x24 arguments are ready to go with alpha and beta
    mov      x2, x25                    ; depth++
    mov      x3, x27                    ; move
    bl       _minmax_min                ; recurse to the MIN

    strb     wzr, [x21, x27]            ; store blank on the board. blank_piece is 0.

    cmp      w0, win_score              ; winning score? 
    b.eq     _minmax_max_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, gt           ; update value if score is > value

    cmp      w23, w26                   ; compare alpha with value
    csel     w23, w26, w23, lt          ; update alpha if alpha is < value

    cmp      w23, w24                   ; compare alpha with beta
    b.lt    _minmax_max_top_of_loop     ; loop to the next board position 0..8

    ; fall through: alpha pruning if alpha >= beta

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
    ; x0: unused (first argument is in x23)
    ; x1: unused (second argument is in x24)
    ; x2: depth. keep in register x25
    ; x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    ; x19: global move count for this thread
    ; x20: winner function table
    ; x21: the board for this thread
    ; x22: global iteration count
    ; x23: alpha (argument)
    ; x24: beta (argument)
    ; x25: next depth
    ; x26: value: local variable
    ; x27: for loop local variable I
    ; x28: the piece to move

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]        
    stp      x29, x30, [sp, #48]       
    add      x29, sp, #48               

    add      x19, x19, 1                ; update global move count

    cmp      x2, 3                      ; can't be a winner if < 5 moves
    b.le     _minmax_min_skip_winner

    ; call the winner function for the most recent move
    mov      x0, x_piece                ; the piece just played
    add      x3, x20, x3, lsl #3        ; calculate the function pointer offset
    ldr      x3, [x3]                   ; grab the function pointer
    blr      x3                         ; call it

    cmp      w0, x_piece                ; did X win?
    mov      w0, win_score              ; move this regardless of the result
    b.eq     _minmax_min_done

    cmp      x2, 8                      ; recursion can only go 8 deep
    mov      x0, tie_score
    b.eq     _minmax_min_done

_minmax_min_skip_winner
    add      x25, x2, 1                 ; next depth
    mov      w28, o_piece               ; making O moves below
    mov      w26, maximum_score         ; the value is maximum because we're minimizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

_minmax_min_top_of_loop
    cmp      x27, 8                     ; check before the increment
    b.eq     _minmax_min_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27               ; save board position in x1 for now and later
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, wzr                    ; is the space free? assumes blank_piece is 0
    b.ne     _minmax_min_top_of_loop

    strb     w28, [x1]                  ; make the move

    ; x23 and x24 arguments are ready to go with alpha and beta
    mov      x2, x25                    ; depth++
    mov      x3, x27                    ; move
    bl       _minmax_max                ; recurse to the MAX

    strb     wzr, [x21, x27]            ; store blank on the board. blank_piece is 0.

    cmp      w0, lose_score             ; losing score? 
    b.eq     _minmax_min_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, lt           ; update value if score is < value

    cmp      w26, w24                   ; compare value with beta
    csel     w24, w26, w24, lt          ; update beta if value < beta

    cmp      w24, w23                   ; compare beta with alpha
    b.gt     _minmax_min_top_of_loop    ; loop to the next board position 0..8

    ; fall through for beta pruning if beta <= alpha

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
        ldrb     w1, [x21, #2]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq ; conditional compare. sets condition flags to result
                                ; of comparison if condition flag (eq) is true or an
                                ; immediate (0) otherise.
                                ; if w1=w1 eq=true else eq=false
        b.eq     pos0_return

        ldrb     w9, [x21, #3]
        ldrb     w1, [x21, #6]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos0_return

        ldrb     w9, [x21, #4]
        and      w0, w0, w9
        ldrb     w1, [x21, #8]
        and      w0, w0, w1

pos0_return
        ret
        ENDP

  align 16
_pos1func PROC
        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #2]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos1_return

        ldrb     w9, [x21, #4]
        and      w0, w0, w9
        ldrb     w1, [x21, #7]
        and      w0, w0, w1

pos1_return
        ret
        ENDP
                     
  align 16
_pos2func PROC
        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #1]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos2_return

        ldrb     w9, [x21, #5]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos2_return

        ldrb     w9, [x21, #4]
        and      w0, w0, w9
        ldrb     w1, [x21, #6]
        and      w0, w0, w1

pos2_return
        ret
        ENDP
                     
  align 16
_pos3func PROC
        ldrb     w9, [x21, #4]
        ldrb     w1, [x21, #5]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos3_return

        ldrb     w9, [x21, #0]
        and      w0, w0, w9
        ldrb     w1, [x21, #6]
        and      w0, w0, w1

pos3_return
        ret
        ENDP

  align 16
_pos4func PROC
        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos4_return

        ldrb     w9, [x21, #2]
        ldrb     w1, [x21, #6]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos4_return

        ldrb     w9, [x21, #1]
        ldrb     w1, [x21, #7]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos4_return

        ldrb     w9, [x21, #3]
        and      w0, w0, w9
        ldrb     w1, [x21, #5]
        and      w0, w0, w1

pos4_return
        ret
        ENDP

  align 16
_pos5func PROC
        ldrb     w9, [x21, #3]
        ldrb     w1, [x21, #4]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos5_return

        ldrb     w9, [x21, #2]
        and      w0, w0, w9
        ldrb     w1, [x21, #8]
        and      w0, w0, w1

pos5_return
        ret
        ENDP

  align 16
_pos6func PROC
        ldrb     w9, [x21, #7]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos6_return

        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #3]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos6_return

        ldrb     w9, [x21, #4]
        ldrb     w1, [x21, #2]
        and      w0, w0, w9
        and      w0, w0, w1

pos6_return
        ret
        ENDP
                  
  align 16
_pos7func PROC
        ldrb     w9, [x21, #6]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos7_return

        ldrb     w9, [x21, #1]
        and      w0, w0, w9
        ldrb     w1, [x21, #4]
        and      w0, w0, w1

pos7_return
        ret
        ENDP

  align 16
_pos8func PROC
        ldrb     w9, [x21, #6]
        ldrb     w1, [x21, #7]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos8_return

        ldrb     w9, [x21, #2]
        ldrb     w1, [x21, #5]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos8_return

        ldrb     w9, [x21, #0]
        and      w0, w0, w9
        ldrb     w1, [x21, #4]
        and      w0, w0, w1

pos8_return
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
