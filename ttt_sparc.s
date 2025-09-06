! prove you can't win at tic-tac-toe if your opponent is competent in sparc v8 assembly.
! g1 pointer to the board
! g2 array of winprocs
! g3 global move count
! g4 current depth
! l1 global loop count
! l2 value
! i0/o0 alpha
! i1/o1 beta
! i2/o2 current move

.equ piece_x, 1
.equ piece_o, 2
.equ piece_blank, 0

.equ score_win, 6
.equ score_tie, 5
.equ score_lose, 4
.equ score_max, 9
.equ score_min, 2
.equ default_iterations, 1

.section .data

.align  2
.board:
    .zero 9
.section .rodata
.moves_string:
    .string "moves: %u\n"
.iterations_string:
    .string "iterations: %u\n"
.align  4
.winprocs:
    .long proc0
    .long proc1
    .long proc2
    .long proc3
    .long proc4
    .long proc5
    .long proc6
    .long proc7
    .long proc8

.section .text    

.align  4
.type proc0, @function
proc0:
    ldub [ %g1 + 0 ], %o0
    ldub [ %g1 + 1 ], %l3
    cmp %o0, %l3
    bne _proc0_next_a
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne,a _proc0_next_a
    nop
    retl
    nop
  _proc0_next_a:
    ldub [ %g1 + 3 ], %l3
    cmp %o0, %l3
    bne _proc0_next_b
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne,a _proc0_next_b
    nop
    retl
    nop
  _proc0_next_b:
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne _proc0_return_0
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc0_return_0
    nop
    retl
    nop
  _proc0_return_0:
    retl
    clr %o0

.align  4
.type proc1, @function
proc1:
    ldub [ %g1 + 1 ], %o0
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc1_next_a
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne,a _proc1_next_a
    nop
    retl
    nop
  _proc1_next_a:
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne _proc1_return_0
    ldub [ %g1 + 7 ], %l3
    cmp %o0, %l3
    bne,a _proc1_return_0
    nop
    retl
    nop
  _proc1_return_0:
    retl
    clr %o0

.align  4
.type proc2, @function
proc2:
    ldub [ %g1 + 2 ], %o0
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc2_next_a
    ldub [ %g1 + 1 ], %l3
    cmp %o0, %l3
    bne,a _proc2_next_a
    nop
    retl
    nop
  _proc2_next_a:
    ldub [ %g1 + 5 ], %l3
    cmp %o0, %l3
    bne _proc2_next_b
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc2_next_b
    nop
    retl
    nop
  _proc2_next_b:
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne _proc2_return_0
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne,a _proc2_return_0
    nop
    retl
    nop
  _proc2_return_0:
    retl
    clr %o0

.align  4
.type proc3, @function
proc3:
    ldub [ %g1 + 3 ], %o0
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc3_next_a
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne,a _proc3_next_a
    nop
    retl
    nop
  _proc3_next_a:
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne _proc3_return_0
    ldub [ %g1 + 5 ], %l3
    cmp %o0, %l3
    bne,a _proc3_return_0
    nop
    retl
    nop
  _proc3_return_0:
    retl
    clr %o0

.align  4
.type proc4, @function
proc4:
    ldub [ %g1 + 4 ], %o0
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc4_next_a
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc4_next_a
    nop
    retl
    nop
  _proc4_next_a:
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne _proc4_next_b
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne,a _proc4_next_b
    nop
    retl
    nop
  _proc4_next_b:
    ldub [ %g1 + 1 ], %l3
    cmp %o0, %l3
    bne _proc4_next_c
    ldub [ %g1 + 7 ], %l3
    cmp %o0, %l3
    bne,a _proc4_next_c
    nop
    retl
    nop
  _proc4_next_c:
    ldub [ %g1 + 3 ], %l3
    cmp %o0, %l3
    bne _proc4_return_0
    ldub [ %g1 + 5 ], %l3
    cmp %o0, %l3
    bne,a _proc4_return_0
    nop
    retl
    nop
  _proc4_return_0:
    retl
    clr %o0

.align  4
.type proc5, @function
proc5:
    ldub [ %g1 + 5 ], %o0
    ldub [ %g1 + 3 ], %l3
    cmp %o0, %l3
    bne _proc5_next_a
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne,a _proc5_next_a
    nop
    retl
    nop
  _proc5_next_a:
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne _proc5_return_0
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc5_return_0
    nop
    retl
    nop
  _proc5_return_0:
    retl
    clr %o0

.align  4
.type proc6, @function
proc6:
    ldub [ %g1 + 6 ], %o0
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne _proc6_next_a
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne,a _proc6_next_a
    nop
    retl
    nop
  _proc6_next_a:
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc6_next_b
    ldub [ %g1 + 3 ], %l3
    cmp %o0, %l3
    bne,a _proc6_next_b
    nop
    retl
    nop
  _proc6_next_b:
    ldub [ %g1 + 7 ], %l3
    cmp %o0, %l3
    bne _proc6_return_0
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc6_return_0
    nop
    retl
    nop
  _proc6_return_0:
    retl
    clr %o0

.align  4
.type proc7, @function
proc7:
    ldub [ %g1 + 7 ], %o0
    ldub [ %g1 + 1 ], %l3
    cmp %o0, %l3
    bne _proc7_next_a
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne,a _proc7_next_a
    nop
    retl
    nop
  _proc7_next_a:
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne _proc7_return_0
    ldub [ %g1 + 8 ], %l3
    cmp %o0, %l3
    bne,a _proc7_return_0
    nop
    retl
    nop
  _proc7_return_0:
    retl
    clr %o0

.align  4
.type proc8, @function
proc8:
    ldub [ %g1 + 8 ], %o0
    ldub [ %g1 + 0 ], %l3
    cmp %o0, %l3
    bne _proc8_next_a
    ldub [ %g1 + 4 ], %l3
    cmp %o0, %l3
    bne,a _proc8_next_a
    nop
    retl
    nop
  _proc8_next_a:
    ldub [ %g1 + 2 ], %l3
    cmp %o0, %l3
    bne _proc8_next_b
    ldub [ %g1 + 5 ], %l3
    cmp %o0, %l3
    bne,a _proc8_next_b
    nop
    retl
    nop
  _proc8_next_b:
    ldub [ %g1 + 6 ], %l3
    cmp %o0, %l3
    bne _proc8_return_0
    ldub [ %g1 + 7 ], %l3
    cmp %o0, %l3
    bne,a _proc8_return_0
    nop
    retl
    nop
  _proc8_return_0:
    retl
    clr %o0

.align 4
.type minmax_max, @function
minmax_max:
    .cfi_startproc
    save %sp, -96, %sp
    .cfi_window_save
    .cfi_register 15, 31
    .cfi_def_cfa_register 30

    inc %g3

    cmp %g4, 4
    blt _max_no_winner_check

    sll %i2, 2, %l0
    ld [ %g2 + %l0 ], %l0
    call %l0
    nop
    cmp %o0, piece_o
    bne,a _max_no_winner_check
    nop
    mov score_lose, %i0
    ret
    restore

  _max_no_winner_check:
    mov score_min, %l2
    mov -1, %i2
    inc %g4

  _max_loop:
    cmp %i2, 8
    be _max_load_value_return
    inc %i2                      ! in the delay slot
    ldub [ %g1 + %i2 ], %l0
    tst %l0
    bne _max_loop
    nop

    mov piece_x, %l0
    stb %l0, [ %g1 + %i2 ]
    mov %i0, %o0
    mov %i1, %o1
    mov %i2, %o2
    call minmax_min
    nop
    clrb [ %g1 + %i2 ]

    cmp %o0, score_win           ! can't do better than winning
    be,a _max_restore_value
    mov %o0, %i0

    cmp %o0, %l2
    ble _max_loop

    cmp %o0, %i1                 ! in the delay slot
    bge,a _max_restore_value
    mov %o0, %i0

    mov %o0, %l2
    cmp %l2, %i0
    ble,a _max_loop
    nop

    mov %l2, %i0
    ba,a _max_loop
    nop

  _max_load_value_return:
    mov %l2, %i0

  _max_restore_value:
    dec %g4
    jmp     %i7+8
    restore
.cfi_endproc

.align 4
.type minmax_min, @function
minmax_min:
    .cfi_startproc
    save %sp, -96, %sp
    .cfi_window_save
    .cfi_register 15, 31
    .cfi_def_cfa_register 30

    inc %g3

    cmp %g4, 4
    blt _min_no_winner_check

    sll %i2, 2, %l0              ! in the delay slot
    ld [ %g2 + %l0 ], %l0
    call %l0
    nop
    cmp %o0, piece_x
    bne,a _min_not_x
    nop
    mov score_win, %i0
    ret
    restore

  _min_not_x:
    cmp %g4, 8
    bne,a _min_no_winner_check
    nop
    mov score_tie, %i0
    ret
    restore

  _min_no_winner_check:
    mov score_max, %l2
    mov -1, %i2
    inc %g4

  _min_loop:
    cmp %i2, 8
    be _min_load_value_return
    inc %i2                          ! in the delay slot

    ldub [ %g1 + %i2 ], %l0
    tst %l0
    bne _min_loop

    mov piece_o, %l0                 ! in the delay slot
    stb %l0, [ %g1 + %i2 ]
    mov %i0, %o0
    mov %i1, %o1
    mov %i2, %o2
    call minmax_max
    nop
    clrb [ %g1 + %i2 ]

    cmp %o0, score_lose               ! can't do better than losing
    be,a _min_restore_value
    mov %o0, %i0

    cmp %o0, %l2
    bge _min_loop

    cmp %o0, %i0                      ! in the delay slot
    ble,a _min_restore_value
    mov %o0, %i0

    mov %o0, %l2
    cmp %l2, %i1
    bge,a _min_loop
    nop

    mov %l2, %i1
    ba,a _min_loop
    nop

  _min_load_value_return:
    mov %l2, %i0

  _min_restore_value:
    dec %g4
    jmp   %i7+8
    restore
.cfi_endproc

.align 4
.type run_move, @function
run_move:
    .cfi_startproc
    save %sp, -96, %sp
    .cfi_window_save
    .cfi_register 15, 31
    .cfi_def_cfa_register 30

    sethi %hi(.board), %g1
    add %g1, %lo(.board), %g1
    mov %i0, %l1
    mov piece_x, %l0
    stb %l0, [ %g1 + %i0 ]

    clr %g4           ! clear the global depth
    mov %i0, %o2        ! first move
    mov score_min, %o0  ! alpha
    mov score_max, %o1  ! beta
    call minmax_min
    nop
    
    stb %g0, [ %g1 + %l1 ]

    jmp     %i7+8
    restore
    .cfi_endproc

.section .text.startup,"ax",@progbits
    .align 4
    .global main
    .type main, #function
    .proc 04
main:
    .cfi_startproc
    save %sp, -96, %sp
    .cfi_window_save
    .cfi_register 15, 31
    .cfi_def_cfa_register 30

    mov default_iterations, %l1
    cmp %i0, 2
    bne no_argument
    nop

    ld [%i1 + 4 ], %o0
    call atoi
    nop
    tst %o0
    bne argument_is_good
    nop
    mov default_iterations, %o0
  argument_is_good:
    mov %o0, %l1

  no_argument:
    mov %l1, %l2
    sethi %hi(.winprocs), %g2
    add %g2, %lo(.winprocs), %g2

  next_iteration:
    clr %g3

    mov 0, %o0
    call run_move
    nop
    mov 1, %o0
    call run_move
    nop
    mov 4, %o0
    call run_move
    nop

    subcc %l1, 1, %l1
    bne next_iteration
    
  all_done:
    sethi %hi(.moves_string), %o0
    add %o0, %lo(.moves_string), %o0      
    mov %g3, %o1
    call  printf
    nop

    sethi %hi(.iterations_string), %o0
    add %o0, %lo(.iterations_string), %o0 
    mov %l2, %o1
    call  printf
    nop

    mov   0, %i0
    jmp   %i7+8
    restore
.cfi_endproc

.section .note.GNU-stack,"",@progbits
