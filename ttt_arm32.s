@ arm32 version of proving you can't win at tic-tac-toe if the opponent is competent
@  Build on an arm32 Linux machine using a .sh script like this (tested on Raspberry PI 4):
@     gcc -o $1 $1.s -march=armv8-a -pthread
@
@ per-thread-global registers:
@ r9  = thread-global move count
@ r10 = thread-global pointer to the board (board0, board1, or board4)
@ r11 = thread-global pointer to winner functions

.global main
.code 32
.data

.set iterations, 10000
.set minimum_score, 2
.set maximum_score, 9
.set win_score, 6
.set lose_score, 4
.set tie_score, 5
.set x_piece, 1
.set o_piece, 2
.set blank_piece, 0

.data
  @ allocate separate boards for the 3 unique starting moves so multiple threads can solve in parallel
  @ pi 3 has cache lines of 32 bytes and pi 4 uses 64. Each board must be on a separate cache line
  @ pi 4 multi-core performance is bad regardless of what spacing exists.
    noise:  .space 128
  .p2align 5
    board0: .byte 1,0,0,0,0,0,0,0,0
    noise0: .space 128-9
  .p2align 5 
    board1: .byte 0,1,0,0,0,0,0,0,0
    noise1: .space 128-9
  .p2align 5 
    board4: .byte 0,0,0,0,1,0,0,0,0
    noise4: .space 128-9

  .p2align 3
    priorTicks:         .int 0
    moveCount:          .int 0
    pthread1:           .quad 0
    pthread4:           .quad 0
    timespecPriorSec:   .int 0
    timespecPriorNSec:  .int 0
    timespecCurSec:     .int 0
    timespecCurNSec:    .int 0
    elapString:         .asciz "%s %u milliseconds\n"
    movecountString:    .asciz "%d moves\n"
    serialString:       .asciz "serial:   "
    parallelString:     .asciz "parallel: "
    debugString:        .asciz "%d, %d, %d, %d, "
    intString:          .asciz "%d\n"
    justintString:      .asciz "%d"

.global _winner_functions
    .p2align 3
  _winner_functions:
    .word _pos0func
    .word _pos1func
    .word _pos2func
    .word _pos3func
    .word _pos4func
    .word _pos5func
    .word _pos6func
    .word _pos7func
    .word _pos8func

.text
.p2align 2 
main:
    .cfi_startproc
    push     {ip, lr}

    @ remember the starting tickcount
    bl       clock
    movw     r1, #:lower16:priorTicks
    movt     r1, #:upper16:priorTicks
    str      r0, [r1]

    movw     r1, #:lower16:timespecPriorSec
    movt     r1, #:upper16:timespecPriorSec
    mov      r0, #1   @ monotonic
    bl       clock_gettime

    @ generate the 3 solutions in serial
    mov      r0, #0
    bl       _runmm 
    mov      r0, #1
    bl       _runmm 
    mov      r0, #4
    bl       _runmm 
 
    movw     r0, #:lower16:serialString
    movt     r0, #:upper16:serialString
    bl       _print_elapsed_time        @ show how long it took in serial
    bl       _print_movecount           @ show # of moves, a multiple of 6493
    bl       _solve_threaded            @ now do it in parallel
    movw     r0, #:lower16:parallelString
    movt     r0, #:upper16:parallelString
    bl       _print_elapsed_time        @ show how long it took in parallel
    bl       _print_movecount           @ show # of moves, a multiple of 6493

    mov      r0, #0
    pop      {ip, pc}
    .cfi_endproc

.p2align 2
_print_elapsed_time:
    .cfi_startproc
    push     {ip, lr}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}

    mov      r11, r0   @ save the string to print

    movw     r1, #:lower16:timespecCurSec
    movt     r1, #:upper16:timespecCurSec
    mov      r0, #1   @ monotonic
    bl       clock_gettime

    movw     r0, #:lower16:timespecCurNSec
    movt     r0, #:upper16:timespecCurNSec
    ldr      r0, [r0]

    movw     r1, #:lower16:timespecPriorNSec
    movt     r1, #:upper16:timespecPriorNSec
    ldr      r1, [r1]
    sub      r0, r0, r1

    movw     r1, #:lower16:1000000               @ convert to milliseconds
    movt     r1, #:upper16:1000000
    bl       __aeabi_idiv
    mov      r3, r0

    movw     r0, #:lower16:timespecCurSec
    movt     r0, #:upper16:timespecCurSec
    ldr      r0, [r0]

    movw     r1, #:lower16:timespecPriorSec
    movt     r1, #:upper16:timespecPriorSec
    ldr      r1, [r1]
    sub      r0, r0, r1   

    movw     r1, #:lower16:1000                  @ convert to milliseconds
    movt     r1, #:upper16:1000
    mul      r0, r1, r0

    mov      r1, r11
    add      r2, r0, r3                          @ add the second and nanosecond portions
    movw     r0, #:lower16:elapString
    movt     r0, #:upper16:elapString
    bl       printf

    movw     r1, #:lower16:timespecPriorSec
    movt     r1, #:upper16:timespecPriorSec
    mov      r0, #1   @ monotonic
    bl        clock_gettime

    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {ip, pc}
    .cfi_endproc

.p2align 2
_print_elapsed_time_old:
    .cfi_startproc
    push     {ip, lr}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}
    bl       clock
    movw     r1, #:lower16:priorTicks
    movt     r1, #:upper16:priorTicks
    ldr      r1, [r1]
    sub      r1, r0, r1
    movw     r0, #:lower16:elapString
    movt     r0, #:upper16:elapString
    bl       printf

    @ NOTE: on some platforms (M1 Mac) clock returns wall time. On others (Raspberry PI) it returns total CPU time across all cores
    bl       clock
    movw     r1, #:lower16:priorTicks
    movt     r1, #:upper16:priorTicks
    str      r0, [r1]

    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {ip, pc}
    .cfi_endproc

.p2align 2
_print_movecount:
    push     {ip, lr}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}
    movw     r2, #:lower16:moveCount
    movt     r2, #:upper16:moveCount
    ldr      r1, [r2]
    mov      r0, #0
    str      r0, [r2]
    movw     r0, #:lower16:movecountString
    movt     r0, #:upper16:movecountString
    bl       printf
    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {ip, pc}

.p2align 2
_runmm:
    .cfi_startproc
    push     {ip, lr}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}

    mov      r9, #0                             @ r9 is the move count
    mov      r8, r0                             @ r8 is the initial move    
    movw     r11, #:lower16:_winner_functions   @ r11 is the winner functions lookup table
    movt     r11, #:upper16:_winner_functions

    @ load r10 with the board to use
    cmp      r0, #0
    bne     _runmm_try1
    movw     r10, #:lower16:board0
    movt     r10, #:upper16:board0
    b        _runmm_for

  _runmm_try1:
    cmp      r0, #1
    bne     _runmm_try4
    movw     r10, #:lower16:board1
    movt     r10, #:upper16:board1
    b        _runmm_for

  _runmm_try4:
    @ force the move to be 4 at this point
    mov      r0, #4
    mov      r8, #4
    movw     r10, #:lower16:board4
    movt     r10, #:upper16:board4

  _runmm_for:
    movw     r7, #:lower16:iterations
    movt     r7, #:upper16:iterations

  _runmm_loop:
    mov      r0, #minimum_score         @ alpha
    mov      r1, #maximum_score         @ beta
    mov      r2, #0                     @ depth
    mov      r3, r8                     @ move (0..8)
    bl       _minmax_min
    sub      r7, r7, #1
    cmp      r7, #0
    bne     _runmm_loop

    @ add the number of moves (atomic because multiple threads may do this at once)
    movw     r0, #:lower16:moveCount
    movt     r0, #:upper16:moveCount
    @ldaddal    r1, r1, [r0]
    ldr      r1, [r0]
    add      r1, r1, r9
    str      r1, [r0]

    @movw     r0, #:lower16:intString
    @movt     r0, #:upper16:intString
    @mov      r1, r8
    @bl       printf

    @ exit the function
    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {ip, pc}

.p2align 2
_debug_ttt:
    push     {ip, lr}
    push     {r0, r1, r2, r3}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}

    push     {r3} @move
    movw     r0, #:lower16:debugString
    movt     r0, #:upper16:debugString
    mov      r1, r7 @alpha
    mov      r2, r8 @beta
    mov      r3, r6 @depth
    bl       printf
    pop      {r3}

    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #0]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #1]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #2]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #3]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #4]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #5]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #6]
    bl       printf
    movw     r0, #:lower16:justintString
    movt     r0, #:upper16:justintString
    ldrb     r1, [r10, #7]
    bl       printf
    movw     r0, #:lower16:intString
    movt     r0, #:upper16:intString
    ldrb     r1, [r10, #8]
    bl       printf

    @ exit the function
    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {r0, r1, r2, r3}
    pop      {ip, pc}

.p2align 2
_debug_r0:
    push     {ip, lr}
    push     {r0, r1, r2, r3}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}

    mov      r1, r0
    movw     r0, #:lower16:intString
    movt     r0, #:upper16:intString
    bl       printf

    @ exit the function
    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {r0, r1, r2, r3}
    pop      {ip, pc}
    .cfi_endproc

.p2align 2
_solve_threaded:
    .cfi_startproc
    push     {ip, lr}
    push     {r4, r5, r6, r7, r8, r9, r10, r11}

    @ board1 takes the longest to complete; start it first
    movw     r0, #:lower16:pthread1
    movt     r0, #:upper16:pthread1
    mov      r1, #0
    movw     r2, #:lower16:_runmm
    movt     r2, #:upper16:_runmm
    mov      r3, #1
    bl       pthread_create

    @ create a thread for board4
    movw     r0, #:lower16:pthread4
    movt     r0, #:upper16:pthread4
    mov      r1, #0
    movw     r2, #:lower16:_runmm
    movt     r2, #:upper16:_runmm
    mov      r3, #4
    bl       pthread_create

    @ solve board0 on this thread
    mov      r0, #0
    bl       _runmm

    @ wait for board4 to complete
    movw     r0, #:lower16:pthread4
    movt     r0, #:upper16:pthread4
    ldr      r0, [r0]
    mov      r1, #0
    bl       pthread_join

    @ wait for board1 to complete
    movw     r0, #:lower16:pthread1
    movt     r0, #:upper16:pthread1
    ldr      r0, [r0]
    mov      r1, #0
    bl       pthread_join

    @ exit the function
    pop      {r4, r5, r6, r7, r8, r9, r10, r11}
    pop      {ip,pc}
    .cfi_endproc

.p2align 2
_minmax_max:
    .cfi_startproc
    @ r0:  argument. alpha. keep in register r7
    @ r1:  argument. beta. keep in register r8
    @ r2:  argument. depth. keep in register r6
    @ r3:  argument. move. position of last piece added 0..8. Keep in register for a bit then it's overwritten
    @ r4:  value: local variable
    @ r5:  for loop variable I
    @ r6:  depth
    @ r7:  alpha
    @ r8:  beta
    @ r9:  thread-global move count
    @ r10: thread-global board
    @ r11: thread-global winner function table

    push     {ip, lr}
    push     {r4, r5, r6, r7, r8}  @ skip 9, 10, and 11 for move count, board, and winner functions

    mov      r7, r0                     @ alpha
    mov      r8, r1                     @ beta
    mov      r6, r2                     @ depth
    add      r9, r9, #1                 @ increment global move count

    @bl       _debug_ttt

    cmp      r6, #3                     @ if fewer that 5 moves played, no winner
    ble      _minmax_max_skip_winner

    @ call the winner function for the most recent move
    mov      r0, #o_piece               @ the piece just played
    add      r1, r11, r3, lsl #2        @ table + function offset
    ldr      r1, [r1]                   @ grab the function pointer
    blx      r1                         @ call it

    @bl       _debug_r0

    cmp      r0, #o_piece               @ did O win?
    mov      r0, #lose_score            @ move regardless of whether we'll branch
    beq      _minmax_max_done

  .p2align 2
  _minmax_max_skip_winner:
    mov      r4, #minimum_score         @ the value is minimum because we're maximizing
    mov      r5, #-1                    @ avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_max_top_of_loop:
    add      r5, r5, #1
    cmp      r5, #9
    beq      _minmax_max_loadv_done

    add      r1, r10, r5
    ldrb     r0, [r1]                   @ load the board piece at I in the loop
    cmp      r0, #blank_piece           @ is the space free?
    bne      _minmax_max_top_of_loop

    mov      r0, #x_piece               @ make the move
    strb     r0, [r1]

    mov      r0, r7                     @ alpha
    mov      r1, r8                     @ beta
    add      r2, r6, #1                 @ depth++
    mov      r3, r5                     @ move
    bl       _minmax_min                @ recurse to the MIN

    add      r1, r10, r5                @ address of the board + move
    mov      r2, #blank_piece           @ load blank
    strb     r2, [r1]                   @ store blank on the board

    cmp      r0, #win_score             @ winning score? 
    beq      _minmax_max_done           @ then return

    cmp      r0, r4                     @ compare score with value
    movgt    r4, r0                     @ update value if score is > value

    cmp      r7, r4                     @ compare alpha with value
    movlt    r7, r4                     @ update alpha if alpha is < value

    cmp      r7, r8                     @ compare alpha with beta
    blt      _minmax_max_top_of_loop    @ loop to the next board position 0..8

  .p2align 2
  _minmax_max_loadv_done:
    mov      r0, r4                     @ load the return value with value
  
  .p2align 2
  _minmax_max_done:
    @ exit the function
    pop      {r4, r5, r6, r7, r8}       @ skip 9, 10, and 11 for move count, board, and winner functions
    pop      {ip, pc}
    .cfi_endproc

.p2align 2
_minmax_min:
    .cfi_startproc
    @ r0:  argument. alpha. keep in register r7
    @ r1:  argument. beta. keep in register r8
    @ r2:  argument. depth. keep in register r6
    @ r3:  argument. move. position of last piece added 0..8. Keep in register for a bit then it's overwritten
    @ r4:  value: local variable
    @ r5:  for loop variable I
    @ r6:  depth
    @ r7:  alpha
    @ r8:  beta
    @ r9:  thread-global move count
    @ r10: thread-global board
    @ r11: thread-global winner function table

    push     {ip, lr}
    push     {r4, r5, r6, r7, r8}  @ skip 9, 10, and 11 for move count, board, and winner functions
     
    mov      r7, r0                     @ alpha
    mov      r8, r1                     @ beta
    mov      r6, r2                     @ depth
    add      r9, r9, #1                 @ increment global move count

    @bl       _debug_ttt

    cmp      r6, #3                     @ if fewer that 5 moves played, no winner
    ble      _minmax_min_skip_winner

    @ call the winner function for the most recent move
    mov      r0, #x_piece               @ the piece just played
    add      r1, r11, r3, lsl #2        @ table + function offset
    ldr      r1, [r1]                   @ grab the function pointer
    blx      r1                         @ call it

    @bl       _debug_r0

    cmp      r0, #x_piece               @ did X win?
    mov      r0, #win_score             @ move this regardless of the result
    beq      _minmax_min_done

    cmp      r6, #8                     @ recursion can only go 8 deep
    mov      r0, #tie_score
    beq      _minmax_min_done

  .p2align 2
  _minmax_min_skip_winner:
    mov      r4, #maximum_score         @ the value is maximum because we're minimizing
    mov      r5, #-1                    @ avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_min_top_of_loop:
    add      r5, r5, #1
    cmp      r5, #9
    beq      _minmax_min_loadv_done

    add      r1, r10, r5
    ldrb     r0, [r1]                   @ load the board piece at I in the loop
    cmp      r0, #blank_piece           @ is the space free?
    bne      _minmax_min_top_of_loop

    mov      r0, #o_piece               @ make the move
    strb     r0, [r1]

    mov      r0, r7                     @ alpha
    mov      r1, r8                     @ beta
    add      r2, r6, #1                 @ depth++
    mov      r3, r5                     @ move
    bl       _minmax_max                @ recurse to the MAX

    add      r1, r10, r5                @ address of the board + move
    mov      r2, #blank_piece           @ load blank
    strb     r2, [r1]                   @ store blank on the board

    cmp      r0, #lose_score            @ losing score? 
    beq      _minmax_min_done           @ then return

    cmp      r0, r4                     @ compare score with value
    movlt    r4, r0                     @ update value if score is < value

    cmp      r4, r8                     @ compare value with beta
    movlt    r8, r4                   @ update beta if value < beta

    cmp      r8, r7                     @ compare beta with alpha
    bgt      _minmax_min_top_of_loop    @ loop to the next board position 0..8

  .p2align 2
  _minmax_min_loadv_done:
    mov      r0, r4                     @ load the return value with value
  
  .p2align 2
  _minmax_min_done:
    @ exit the function
    pop      {r4, r5, r6, r7, r8}       @ skip 9, 10, and 11 for move count, board, and winner functions
    pop      {ip, pc}
    .cfi_endproc

.globl _pos0func
.p2align 2
_pos0func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #1]
        cmp      r0, r1
        bne      LBB3_2
        ldrb     r1, [r10, #2]
        cmp      r0, r1
        beq      LBB3_7
  LBB3_2:
        ldrb     r1, [r10, #3]
        cmp      r0, r1
        bne      LBB3_4
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        beq      LBB3_7
  LBB3_4:
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        bne      LBB3_6
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB3_7
  LBB3_6:
        mov      r0, #0
  LBB3_7:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos1func
.p2align 2
_pos1func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10]
        cmp      r0, r1
        bne      LBB4_2
        ldrb     r1, [r10, #2]
        cmp      r0, r1
        beq      LBB4_5
  LBB4_2:
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        bne      LBB4_4
        ldrb     r1, [r10, #7]
        cmp      r0, r1
        beq      LBB4_5
  LBB4_4:
        mov      r0, #0
  LBB4_5:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos2func
.p2align 2
_pos2func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10]
        cmp      r0, r1
        bne      LBB5_2
        ldrb     r1, [r10, #1]
        cmp      r0, r1
        beq      LBB5_7
  LBB5_2:
        ldrb     r1, [r10, #5]
        cmp          r0, r1
        bne      LBB5_4
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB5_7
  LBB5_4:
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        bne      LBB5_6
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        beq      LBB5_7
  LBB5_6:
        mov      r0, #0
  LBB5_7:
        pop      {ip, pc}
    .cfi_endproc                 

.globl _pos3func
.p2align 2
_pos3func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        bne      LBB6_2
        ldrb     r1, [r10, #5]
        cmp      r0, r1
        beq      LBB6_5
  LBB6_2:
        ldrb     r1, [r10]
        cmp      r0, r1
        bne      LBB6_4
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        beq      LBB6_5
  LBB6_4:
        mov      r0, #0
  LBB6_5:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos4func
.p2align 2
_pos4func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10]
        cmp      r0, r1
        bne      LBB7_2
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB7_9
  LBB7_2:
        ldrb     r1, [r10, #2]
        cmp          r0, r1
        bne      LBB7_4
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        beq      LBB7_9
  LBB7_4:
        ldrb     r1, [r10, #1]
        cmp      r0, r1
        bne      LBB7_6
        ldrb     r1, [r10, #7]
        cmp      r0, r1
        beq      LBB7_9
  LBB7_6:
        ldrb     r1, [r10, #3]
        cmp      r0, r1
        bne      LBB7_8
        ldrb     r1, [r10, #5]
        cmp      r0, r1
        beq      LBB7_9
  LBB7_8:
        mov      r0, #0
  LBB7_9:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos5func
.p2align 2
_pos5func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #3]
        cmp      r0, r1
        bne      LBB8_2
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        beq      LBB8_5
  LBB8_2:
        ldrb     r1, [r10, #2]
        cmp      r0, r1
        bne      LBB8_4
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB8_5
  LBB8_4:
        mov      r0, #0
  LBB8_5:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos6func
.p2align 2
_pos6func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #7]
        cmp      r0, r1
        bne      LBB9_2
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB9_7
  LBB9_2:
        ldrb     r1, [r10]
        cmp      r0, r1
        bne      LBB9_4
        ldrb     r1, [r10, #3]
        cmp      r0, r1
        beq      LBB9_7
  LBB9_4:
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        bne      LBB9_6
        ldrb     r1, [r10, #2]
        cmp      r0, r1
        beq      LBB9_7
  LBB9_6:
        mov      r0, #0
  LBB9_7:
        pop      {ip, pc}
     .cfi_endproc

.globl _pos7func
.p2align 2
_pos7func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        bne      LBB10_2
        ldrb     r1, [r10, #8]
        cmp      r0, r1
        beq      LBB10_5
  LBB10_2:
        ldrb     r1, [r10, #1]
        cmp      r0, r1
        bne      LBB10_4
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        beq      LBB10_5
  LBB10_4:
        mov      r0, #0
  LBB10_5:
        pop      {ip, pc}
    .cfi_endproc

.globl _pos8func
.p2align 2
_pos8func:
    .cfi_startproc
        push     {ip, lr}
        ldrb     r1, [r10, #6]
        cmp      r0, r1
        bne     LBB11_2
        ldrb     r1, [r10, #7]
        cmp      r0, r1
        beq     LBB11_7
  LBB11_2:
        ldrb     r1, [r10, #2]
        cmp      r0, r1
        bne     LBB11_4
        ldrb     r1, [r10, #5]
        cmp      r0, r1
        beq     LBB11_7
  LBB11_4:
        ldrb     r1, [r10]
        cmp      r0, r1
        bne     LBB11_6
        ldrb     r1, [r10, #4]
        cmp      r0, r1
        beq     LBB11_7
  LBB11_6:
        mov      r0, #0
  LBB11_7:
        pop      {ip, pc}
    .cfi_endproc


