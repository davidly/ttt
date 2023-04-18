// build on an Arm64 Linux machine using:
//  gcc -o ttt_gnu_arm64 ttt_gnu_arm64.s -march=native -mcpu=native -lpthread -static
//

.global main

.set iterations, 100000
.set minimum_score, 2
.set maximum_score, 9
.set win_score, 6
.set lose_score, 4
.set tie_score, 5
.set x_piece, 1
.set o_piece, 2
.set blank_piece, 0                     // the code below assumes this is 0

.data
  // allocate separate boards for the 3 unique starting moves so multiple threads can solve in parallel
  .p2align 6
    board0: .byte 1,0,0,0,0,0,0,0,0
  .p2align 6
    board1: .byte 0,1,0,0,0,0,0,0,0
  .p2align 6 
    board4: .byte 0,0,0,0,1,0,0,0,0

  .p2align 4
    priorTicks:      .quad 0
    moveCount:       .quad 0
    pthread1:        .quad 0
    pthread4:        .quad 0
    elapString:      .asciz "%lld microseconds (-6)\n"
    movecountString: .asciz "%d moves\n"
    itersString:     .asciz "%d iterations\n"
    startString:     .asciz "starting\n"
 
.text
.p2align 2 
main:
    // remember the caller's stack frame and return address
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    adrp     x0, startString
    add      x0, x0, :lo12:startString
    bl       call_printf                

    // remember the starting tickcount
    adrp     x1, priorTicks
    add      x1, x1, :lo12:priorTicks
    mrs      x0, cntvct_el0
    str      x0, [x1]

    // generate the 3 solutions in serial
    mov      x0, 0
    bl       _runmm 
    mov      x0, 1
    bl       _runmm 
    mov      x0, 4
    bl       _runmm 
 
    bl       _print_elapsed_time        // show how long it took in serial
    bl       _print_movecount           // show # of moves, a multiple of 6493
    bl       _solve_threaded            // now do it in parallel
    bl       _print_elapsed_time        // show how long it took in parallel
    bl       _print_movecount           // show # of moves, a multiple of 6493

    mov      x0, 0
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.p2align 2
_print_elapsed_time:
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    mrs      x1, cntvct_el0             // current tick time in x1
    adrp     x3, priorTicks        // load prior tick count
    add      x3, x3, :lo12:priorTicks
    ldr      x0, [x3]
    str      x1, [x3]                   // update prior with current time
    sub      x1, x1, x0
    ldr      x4, =0xf4240               // 1,000,000 (microseconds)
    mul      x1, x1, x4                 // save precision by multiplying by a big number
    mrs      x2, cntfrq_el0             // get the divisor and divide
    udiv     x1, x1, x2
    adrp     x0, elapString
    add      x0, x0, :lo12:elapString
    bl       call_printf                // print the elapsed time
    
    ldr      x1, =iterations
    adrp     x0, itersString
    add      x0, x0, :lo12:itersString
    bl       call_printf

    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.p2align 2
_print_movecount:
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    adrp     x0, moveCount
    add      x0, x0, :lo12:moveCount
    ldr      w1, [x0]
    str      xzr, [x0]                    // reset moveCount to 0   
    adrp     x0, movecountString
    add      x0, x0, :lo12:movecountString
    bl       call_printf

    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.p2align 2
_runmm:
    // the pthread infra needs many these registers to be saved (especially x20)

    stp      x26, x25, [sp, #-96]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]        
    stp      x22, x21, [sp, #48]
    stp      x20, x19, [sp, #64]       
    stp      x29, x30, [sp, #80]       
    add      x29, sp, #80               

    mov      x19, 0                              // x19 is the move count
    mov      x27, x0                             // x27 is the initial move    
    adrp     x20, _winner_functions         // x20 holds the function table
    add      x20, x20, :lo12:_winner_functions

    // load x21 with the board to use
    cmp      x0, 0
    b.ne     _runmm_try1
    adrp     x21, board0
    add      x21, x21, :lo12:board0
    b        _runmm_for

  _runmm_try1:
    cmp      x0, 1
    b.ne     _runmm_try4
    adrp     x21, board1
    add      x21, x21, :lo12:board1
    b        _runmm_for

  _runmm_try4:
    // force the move to be 4 at this point
    mov      x0, 4
    mov      x27, 4
    adrp     x21, board4
    add      x21, x21, :lo12:board4

  _runmm_for:
    ldr      x22, =iterations           // x22 is the iteration for loop counter. ldr not mov because it's large

  _runmm_loop:
    mov      x23, minimum_score         // alpha
    mov      x24, maximum_score         // beta
    mov      x2, 0                      // depth
    mov      x3, x27                    // move (0..8)
    bl       _minmax_min
    sub      x22, x22, 1
    cmp      x22, 0
    b.ne     _runmm_loop

    // add the number of moves (atomic because multiple threads may do this at once)
    adrp     x0, moveCount
    add      x0, x0, :lo12:moveCount
    //ldaddal  w19, w19, [x0]      // I can't get the gnu assembler to use ldaddal. code below isn't thread-safe
    ldr      x1, [x0]
    add      x1, x1, x19
    str      x1, [x0]

    // exit the function
    ldp      x29, x30, [sp, #80]
    ldp      x20, x19, [sp, #64]         
    ldp      x22, x21, [sp, #48]        
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #96        
    ret

.p2align 2
_solve_threaded:
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    // board1 takes the longest to complete// start it first
    adrp     x0, pthread1
    add      x0, x0, :lo12:pthread1
    mov      x1, 0
    adrp     x2, _runmm
    add      x2, x2, :lo12:_runmm
    mov      x3, 1
    bl       pthread_create

    // created a thread for board4
    adrp     x0, pthread4
    add      x0, x0, :lo12:pthread4
    mov      x1, 0
    adrp     x2, _runmm
    add      x2, x2, :lo12:_runmm
    mov      x3, 4
    bl       pthread_create

    // solve board0 on this thread
    mov      x0, 0
    bl       _runmm

    // wait for board1 to complete
    adrp     x0, pthread1
    add      x0, x0, :lo12:pthread1
    ldr      x0, [x0]
    mov      x1, 0
    bl       pthread_join

    // wait for board4 to complete
    adrp     x0, pthread4
    add      x0, x0, :lo12:pthread4
    ldr      x0, [x0]
    mov      x1, 0
    bl       pthread_join

    // exit the function
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.p2align 2
_minmax_max:
    // x0: unused (first argument is in x23)
    // x1: unused (second argument is in x24)
    // x2: depth. keep in register x25
    // x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    // x19: global move count for this thread
    // x20: winner function table
    // x21: the board for this thread
    // x22: global iteration count
    // x23: alpha (argument)
    // x24: beta (argument)
    // x25: depth
    // x26: value: local variable
    // x27: for loop local variable I
    // x28: the move to make (X)

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]         
    stp      x29, x30, [sp, #48]        
    add      x29, sp, #48               

    mov      x25, x2                    // depth
    add      x19, x19, 1                // increment global move count

    cmp      x25, 3                     // if fewer that 5 moves played, no winner
    b.le     _minmax_max_skip_winner

    // call the winner function for the most recent move
    mov      x0, o_piece                // the piece just played
    add      x3, x20, x3, lsl #3        // table + function offset
    ldr      x3, [x3]                   // grab the function pointer
    blr      x3                         // call it

    cmp      w0, o_piece                // did O win?
    mov      w0, lose_score             // move regardless of whether we'll branch
    b.eq     _minmax_max_done

  .p2align 2
  _minmax_max_skip_winner:
    mov      w28, x_piece               // making X moves below
    mov      w26, minimum_score         // the value is minimum because we're maximizing
    mov      x27, -1                    // avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_max_top_of_loop:
    cmp      x27, 8                     // check before the increment
    b.eq     _minmax_max_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27
    ldrb     w0, [x1]                   // load the board piece at I in the loop
    cmp      w0, wzr                    // is the space free? assumes blank_piece is 0
    b.ne     _minmax_max_top_of_loop

    strb     w28, [x1]                  // make the move

    // x23 and x24 arguments are ready to go with alpha and beta
    add      x2, x25, 1                 // depth++
    mov      x3, x27                    // move
    bl       _minmax_min                // recurse to the MIN

    strb     wzr, [x21, x27]            // store blank on the board. blank_piece is 0.

    cmp      w0, win_score              // winning score? 
    b.eq     _minmax_max_done           // then return

    cmp      w0, w26                    // compare score with value
    csel     w26, w0, w26, gt           // update value if score is > value

    cmp      w23, w26                   // compare alpha with value
    csel     w23, w26, w23, lt          // update alpha if alpha is < value

    cmp      w23, w24                   // compare alpha with beta
    b.lt     _minmax_max_top_of_loop    // loop to the next board position 0..8

    // fall through for alpha pruning if alpha >= beta

  .p2align 2
  _minmax_max_loadv_done:
    mov      x0, x26                    // load the return value with value
  
  .p2align 2
  _minmax_max_done:
    ldp      x29, x30, [sp, #48]         
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #64        
    ret

.p2align 2
_minmax_min:
    // x0: unused (first argument is in x23)
    // x1: unused (second argument is in x24)
    // x2: depth. keep in register x25
    // x3: move: position of last piece added 0..8. Keep in register for a bit then it's overwritten
    // x19: global move count for this thread
    // x20: winner function table
    // x21: the board for this thread
    // x22: global iteration count
    // x23: alpha (argument)
    // x24: beta (argument)
    // x25: depth
    // x26: value: local variable
    // x27: for loop local variable I
    // x28: the move to make (O)

    stp      x26, x25, [sp, #-64]!      
    stp      x24, x23, [sp, #16]        
    stp      x28, x27, [sp, #32]        
    stp      x29, x30, [sp, #48]       
    add      x29, sp, #48               

    mov      x25, x2                    // depth
    add      x19, x19, 1                // update global move count

    cmp      x25, 3                     // can't be a winner if < 5 moves
    b.le     _minmax_min_skip_winner

    // call the winner function for the most recent move
    mov      x0, x_piece                // the piece just played
    add      x3, x20, x3, lsl #3        // table + function offset
    ldr      x3, [x3]                   // grab the function pointer
    blr      x3                         // call it

    cmp      w0, x_piece                // did X win?
    mov      w0, win_score              // move this regardless of the result
    b.eq     _minmax_min_done

    cmp      x25, 8                     // recursion can only go 8 deep
    mov      x0, tie_score
    b.eq     _minmax_min_done

  .p2align 2
  _minmax_min_skip_winner:
    mov      w28, o_piece               // the move to make below
    mov      w26, maximum_score         // the value is maximum because we're minimizing
    mov      x27, -1                    // avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_min_top_of_loop:
    cmp      x27, 8
    b.eq     _minmax_min_loadv_done
    add      x27, x27, 1

    add      x1, x21, x27               // board + move is the address of the piece
    ldrb     w0, [x1]                   // load the board piece at I in the loop
    cmp      w0, wzr                    // is the space free? assumes blank_piece is 0
    b.ne     _minmax_min_top_of_loop

    strb     w28, [x1]                  // store the move on the board

    // x23 and x24 arguments are ready to go with alpha and beta
    add      x2, x25, 1                 // depth + 1
    mov      x3, x27                    // move
    bl       _minmax_max                // recurse to the MAX

    strb     wzr, [x21, x27]            // store blank on the board. blank_piece is 0.

    cmp      w0, lose_score             // losing score? 
    b.eq     _minmax_min_done           // then return

    cmp      w0, w26                    // compare score with value
    csel     w26, w0, w26, lt           // update value if score is < value

    cmp      w26, w24                   // compare value with beta
    csel     w24, w26, w24, lt          // update beta if value < beta

    cmp      w24, w23                   // compare beta with alpha
    b.gt     _minmax_min_top_of_loop    // loop to the next board position 0..8

    // fall through for beta pruning if beta <= alpha

  .p2align 2
  _minmax_min_loadv_done:
    mov      x0, x26                    // load the return value with value
  
  .p2align 2
  _minmax_min_done:
    ldp      x29, x30, [sp, #48]        
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #64        
    ret

.p2align 2
call_printf:
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16
    str      x1, [sp]
    bl       printf
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.globl _pos0func
.p2align 2
_pos0func:
        .cfi_startproc
        ldrb     w9, [x21, #1]
        ldrb     w1, [x21, #2]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos0_return

        ldrb     w9, [x21, #3]
        ldrb     w1, [x21, #6]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos0_return

        ldrb     w9, [x21, #4]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos0_return:
        ret
        .cfi_endproc

.globl _pos1func
.p2align 2
_pos1func:
        .cfi_startproc
        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #2]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos1_return

        ldrb     w9, [x21, #4]
        ldrb     w1, [x21, #7]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos1_return:
        ret
        .cfi_endproc
                     
.globl _pos2func
.p2align 2
_pos2func:
        .cfi_startproc
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
        ldrb     w1, [x21, #6]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos2_return:
        ret
        .cfi_endproc
                     
.globl _pos3func
.p2align 2
_pos3func:
        .cfi_startproc
        ldrb     w9, [x21, #4]
        ldrb     w1, [x21, #5]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos3_return

        ldrb     w9, [x21, #0]
        ldrb     w1, [x21, #6]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos3_return:
        ret
        .cfi_endproc

.globl _pos4func
.p2align 2
_pos4func:
        .cfi_startproc
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
        ldrb     w1, [x21, #5]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos4_return:
        ret
        .cfi_endproc

.globl _pos5func
.p2align 2
_pos5func:
        .cfi_startproc
        ldrb     w9, [x21, #3]
        ldrb     w1, [x21, #4]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos5_return

        ldrb     w9, [x21, #2]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos5_return:
        ret
        .cfi_endproc

.globl _pos6func
.p2align 2
_pos6func:
        .cfi_startproc
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
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos6_return:
        ret
        .cfi_endproc
                  
.globl _pos7func
.p2align 2
_pos7func:
        .cfi_startproc
        ldrb     w9, [x21, #6]
        ldrb     w1, [x21, #8]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        b.eq     pos7_return

        ldrb     w9, [x21, #1]
        ldrb     w1, [x21, #4]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos7_return:
        ret
        .cfi_endproc

.globl _pos8func
.p2align 2
_pos8func:
        .cfi_startproc
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
        ldrb     w1, [x21, #4]
        cmp      w0, w9
        ccmp     w0, w1, #0, eq
        csel     w0, wzr, w0, ne

pos8_return:
        ret

        .cfi_endproc

.data
.globl _winner_functions
        .p2align 3
_winner_functions:
    .quad _pos0func
    .quad _pos1func
    .quad _pos2func
    .quad _pos3func
    .quad _pos4func
    .quad _pos5func
    .quad _pos6func
    .quad _pos7func
    .quad _pos8func
