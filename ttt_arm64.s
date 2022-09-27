; build on an Apple Silicon Mac using a script like this:
; as -arch arm64 $1.s -o $1.o
; ld $1.o -o $1 -syslibroot 'xcrun -sdk macos --show-sdk-path' -e _start -L /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib -lSystem
;
; what's specific to MacOS? The arguments to printf. I think everything else is generic arm64.

.global _start

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
  ; allocate separate boards for the 3 unique starting moves so multiple threads can solve in parallel
  .p2align 3
    board0: .byte 1,0,0,0,0,0,0,0,0
  .p2align 3 
    board1: .byte 0,1,0,0,0,0,0,0,0
  .p2align 3 
    board4: .byte 0,0,0,0,1,0,0,0,0

  .p2align 3
    startTicks:      .quad 0
    moveCount:       .quad 0
    elapString:      .asciz "%lld microseconds (-6)\n"
    movecountString: .asciz "%d moves\n"
    startString:     .asciz "start\n"
    stopString:      .asciz "stop\n"

.text
.p2align 2 
_start:
    ; remember the caller's stack frame and return address (though we never use it due to the exit())
    
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    ; keep this parked in x20 for fast access

    adrp     x20, _winner_functions@PAGE
    add      x20, x20, _winner_functions@PAGEOFF

    ; show that we're starting execution

    adrp     x0, startString@PAGE
    add      x0, x0, startString@PAGEOFF
    bl       call_printf

    ; remember the starting tickcount
   
    adrp     x1, startTicks@PAGE
    add      x1, x1, startTicks@PAGEOFF
    mrs      x0, cntvct_el0
    str      x0, [x1]

    ; generate the 3 solutions

  .p2align 2
    mov      x0, 0
    bl       _runmm 
    mov      x0, 1
    bl       _runmm 
    mov      x0, 4
    bl       _runmm 
 
    ; show execution time

    adrp     x3, startTicks@PAGE
    add      x3, x3, startTicks@PAGEOFF
    ldr      x0, [x3]
    mrs      x1, cntvct_el0
    sub      x1, x1, x0
    ldr      x4, =0xf4240
    mul      x1, x1, x4
    mrs      x2, cntfrq_el0
    udiv     x1, x1, x2
    adrp     x0, elapString@PAGE
    add      x0, x0, elapString@PAGEOFF
    bl       call_printf

    ; show the move count (should be a multiple of 6493)

    adrp     x0, moveCount@PAGE
    add      x0, x0, moveCount@PAGEOFF
    ldr      w1, [x0]   
    adrp     x0, movecountString@PAGE
    add      x0, x0, movecountString@PAGEOFF
    bl       call_printf

    ; show that we're ending execution

    adrp     x0, stopString@PAGE
    add      x0, x0, stopString@PAGEOFF
    bl       call_printf

    ; call the c runtime to exit the app

    mov      x0, 0
    bl       _exit
 
.p2align 2
_runmm:
    sub      sp, sp, #32
    stp      x29, x30, [sp, #16]
    add      x29, sp, #16

    mov      x19, 0                     ; x19 is the move count
    mov      x23, x0                    ; x23 is the initial move
    
    ; load x21 with the board to use

    cmp      x0, 0
    b.ne     _runmm_try1
    adrp     x21, board0@PAGE
    add      x21, x21, board0@PAGEOFF
    b        _runmm_for

  _runmm_try1:
    cmp      x0, 1
    b.ne     _runmm_try4
    adrp     x21, board1@PAGE
    add      x21, x21, board1@PAGEOFF
    b        _runmm_for

  _runmm_try4:
    ; force the move to be 4 at this point
    mov      x0, 4
    mov      x23, 4
    adrp     x21, board4@PAGE
    add      x21, x21, board4@PAGEOFF

  _runmm_for:
    mov      x22, iterations            ; x22 is the iteration for loop counter

  _runmm_loop:
    mov      x0, minimum_score          ; alpha
    mov      x1, maximum_score          ; beta
    mov      x2, 0                      ; depth
    mov      x3, x23                    ; move (0..8)
    bl       _minmax_min
    sub      x22, x22, 1
    cmp      x22, 0
    b.ne     _runmm_loop

    ; add the number of moves (atomic because multiple threads may do this at once)
    
    adrp     x0, moveCount@PAGE
    add      x0, x0, moveCount@PAGEOFF
    ldaddal  w19, w19, [x0]

    ; exit the function

    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.p2align 2
_minmax_max:
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
    ; x27: for loop variable I
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

  .p2align 2
  _minmax_max_skip_winner:
    mov      w26, minimum_score         ; the value is minimum because we're maximizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_max_top_of_loop:
    add      x27, x27, 1
    cmp      x27, 9
    b.eq     _minmax_max_loadv_done

    add      x1, x21, x27
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, blank_piece            ; is the space free?
    b.ne     _minmax_max_top_of_loop

    mov      w2, x_piece                ; make the move
    strb     w2, [x1]

    mov      x0, x23                    ; alpha
    mov      x1, x24                    ; beta
    add      x2, x25, 1                 ; depth++
    mov      x3, x27                    ; move
    bl       _minmax_min                ; recurse to the MIN

    add      x6, x21, x27               ; address of the board + move
    mov      x7, blank_piece            ; load blank
    strb     w7, [x6]                   ; store blank on the board

    cmp      w0, win_score              ; winning score? 
    b.eq     _minmax_max_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, gt           ; update value if score is > value

    cmp      w23, w26                   ; compare alpha with value
    csel     w23, w26, w23, lt          ; update alpha if alpha is < value

    cmp      w23, w24                   ; compare alpha with beta
    b.ge     _minmax_max_loadv_done     ; alpha pruning if alpha >= beta
 
    b        _minmax_max_top_of_loop

  .p2align 2
  _minmax_max_loadv_done:
    mov      x0, x26                    ; load the return value with value
  
  .p2align 2
  _minmax_max_done:
    ldp      x29, x30, [sp, #48]         
    ldp      x28, x27, [sp, #32]        
    ldp      x24, x23, [sp, #16]        
    ldp      x26, x25, [sp], #64        
    ret

.p2align 2
_minmax_min:
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
    ; x27: for loop variable I
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

  .p2align 2
  _minmax_min_skip_winner:
    mov      w26, maximum_score         ; the value is maximum because we're minimizing
    mov      x27, -1                    ; avoid a jump by starting the for loop I at -1

  .p2align 2
  _minmax_min_top_of_loop:
    add      x27, x27, 1
    cmp      x27, 9
    b.eq     _minmax_min_loadv_done

    add      x1, x21, x27               ; board + move is the address of the piece
    ldrb     w0, [x1]                   ; load the board piece at I in the loop
    cmp      w0, blank_piece            ; is the space free?
    b.ne     _minmax_min_top_of_loop

    mov      w2, o_piece                ; the move is O
    strb     w2, [x1]                   ; store the move on the board

    mov      x0, x23                    ; alpha
    mov      x1, x24                    ; beta
    add      x2, x25, 1                 ; depth + 1
    mov      x3, x27                    ; move
    bl       _minmax_max                ; recurse to the MAX

    add      x6, x21, x27               ; address of the board + move
    mov      x7, blank_piece            ; load blank
    strb     w7, [x6]                   ; store blank on the board

    cmp      w0, lose_score             ; losing score? 
    b.eq     _minmax_min_done           ; then return

    cmp      w0, w26                    ; compare score with value
    csel     w26, w0, w26, lt           ; update value if score is < value

    cmp      w26, w24                   ; compare value with beta
    csel     w24, w26, w24, lt          ; update beta if value < beta

    cmp      w24, w23                   ; compare beta with alpha
    b.le     _minmax_min_loadv_done     ; beta pruning if beta <= alpha
 
    b        _minmax_min_top_of_loop

  .p2align 2
  _minmax_min_loadv_done:
    mov      x0, x26                    ; load the return value with value
  
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
    bl       _printf
    ldp      x29, x30, [sp, #16]
    add      sp, sp, #32
    ret

.globl _pos0func
.p2align 2
_pos0func:
	.cfi_startproc
	ldrb	 w9, [x21, #1]
	cmp      w0, w9
	b.ne	 LBB3_2
	ldrb	 w9, [x21, #2]
	cmp      w0, w9
	b.eq	 LBB3_7
  LBB3_2:
	ldrb	 w9, [x21, #3]
	cmp      w0, w9
	b.ne	 LBB3_4
	ldrb	 w9, [x21, #6]
	cmp      w0, w9
	b.eq	 LBB3_7
  LBB3_4:
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.ne	 LBB3_6
	ldrb	 w8, [x21, #8]
	cmp      w0, w8
	b.eq	 LBB3_7
  LBB3_6:
	mov      w0, #0
  LBB3_7:
	ret
	.cfi_endproc

.globl _pos1func
.p2align 2
_pos1func:
	.cfi_startproc
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB4_2
	ldrb	 w9, [x21, #2]
	cmp      w0, w9
	b.eq	 LBB4_5
  LBB4_2:
	ldrb     w9, [x21, #4]
	cmp      w0, w9
	b.ne	 LBB4_4
	ldrb	 w8, [x21, #7]
	cmp      w0, w8
	b.eq	 LBB4_5
  LBB4_4:
	mov      w0, #0
  LBB4_5:
	ret
	.cfi_endproc
                     
	.globl _pos2func
	.p2align 2
_pos2func:
	.cfi_startproc
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB5_2
	ldrb	 w9, [x21, #1]
	cmp      w0, w9
	b.eq	 LBB5_7
  LBB5_2:
	ldrb	 w9, [x21, #5]
	cmp	     w0, w9
	b.ne	 LBB5_4
	ldrb 	 w9, [x21, #8]
	cmp      w0, w9
	b.eq	 LBB5_7
  LBB5_4:
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.ne	 LBB5_6
	ldrb	 w8, [x21, #6]
	cmp      w0, w8
	b.eq	 LBB5_7
  LBB5_6:
	mov      w0, #0
  LBB5_7:
	ret
	.cfi_endproc
                     
	.globl _pos3func
	.p2align 2
_pos3func:
	.cfi_startproc
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.ne	 LBB6_2
	ldrb	 w9, [x21, #5]
	cmp      w0, w9
	b.eq	 LBB6_5
  LBB6_2:
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB6_4
	ldrb	 w8, [x21, #6]
	cmp      w0, w8
	b.eq	 LBB6_5
  LBB6_4:
	mov      w0, #0
  LBB6_5:
	ret
	.cfi_endproc

	.globl	_pos4func
	.p2align 2
_pos4func:
	.cfi_startproc
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB7_2
	ldrb	 w9, [x21, #8]
	cmp      w0, w9
	b.eq	 LBB7_9
  LBB7_2:
	ldrb	 w9, [x21, #2]
	cmp	     w0, w9
	b.ne	 LBB7_4
	ldrb	 w9, [x21, #6]
	cmp      w0, w9
	b.eq	 LBB7_9
  LBB7_4:
	ldrb	 w9, [x21, #1]
	cmp      w0, w9
	b.ne	 LBB7_6
	ldrb	 w9, [x21, #7]
	cmp      w0, w9
	b.eq	 LBB7_9
  LBB7_6:
	ldrb	 w9, [x21, #3]
	cmp      w0, w9
	b.ne	 LBB7_8
	ldrb	 w8, [x21, #5]
	cmp      w0, w8
	b.eq	 LBB7_9
  LBB7_8:
	mov      w0, #0
  LBB7_9:
	ret
	.cfi_endproc

	.globl	_pos5func
	.p2align 2
_pos5func:
	.cfi_startproc
	ldrb	 w9, [x21, #3]
	cmp      w0, w9
	b.ne	 LBB8_2
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.eq	 LBB8_5
  LBB8_2:
	ldrb	 w9, [x21, #2]
	cmp      w0, w9
	b.ne	 LBB8_4
	ldrb	 w8, [x21, #8]
	cmp      w0, w8
	b.eq	 LBB8_5
  LBB8_4:
	mov      w0, #0
  LBB8_5:
	ret
	.cfi_endproc

	.globl	_pos6func
	.p2align 2
_pos6func:
	.cfi_startproc
	ldrb	 w9, [x21, #7]
	cmp      w0, w9
	b.ne	 LBB9_2
	ldrb	 w9, [x21, #8]
	cmp      w0, w9
	b.eq	 LBB9_7
  LBB9_2:
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB9_4
	ldrb     w9, [x21, #3]
	cmp      w0, w9
	b.eq	 LBB9_7
  LBB9_4:
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.ne	 LBB9_6
	ldrb	 w8, [x21, #2]
	cmp      w0, w8
	b.eq	 LBB9_7
  LBB9_6:
	mov      w0, #0
  LBB9_7:
	ret
	.cfi_endproc
                  
	.globl	_pos7func
	.p2align 2
_pos7func:
	.cfi_startproc
	ldrb	 w9, [x21, #6]
	cmp      w0, w9
	b.ne	 LBB10_2
	ldrb	 w9, [x21, #8]
	cmp      w0, w9
	b.eq	 LBB10_5
  LBB10_2:
	ldrb	 w9, [x21, #1]
	cmp      w0, w9
	b.ne	 LBB10_4
	ldrb	 w9, [x21, #4]
	cmp      w0, w9
	b.eq	 LBB10_5
  LBB10_4:
	mov      w0, #0
  LBB10_5:
	ret
	.cfi_endproc

	.globl	_pos8func
	.p2align 2
_pos8func:
	.cfi_startproc
	ldrb	 w9, [x21, #6]
	cmp      w0, w9
	b.ne	 LBB11_2
	ldrb	 w9, [x21, #7]
	cmp      w0, w9
	b.eq	 LBB11_7
  LBB11_2:
	ldrb	 w9, [x21, #2]
	cmp      w0, w9
	b.ne	 LBB11_4
	ldrb	 w9, [x21, #5]
	cmp      w0, w9
	b.eq	 LBB11_7
  LBB11_4:
	ldrb	 w9, [x21]
	cmp      w0, w9
	b.ne	 LBB11_6
	ldrb	 w8, [x21, #4]
	cmp      w0, w8
	b.eq	 LBB11_7
  LBB11_6:
	mov      w0, #0
  LBB11_7:
	ret
	.cfi_endproc

.section __DATA, __data
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
