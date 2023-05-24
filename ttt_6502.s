;
; Apple 1 / 6502 implementation of proving you can't win at tic-tac-toe.
; Tested on the RetroTechLyfe Apple 1 clone computer and the POM1 Apple 1 emulator.
; The moves variable should contain 6493 decimal / 0x195d hex if it's running correctly.
;
; Assemble with sbasm30306\sbasm.py ttt.s
; sbasm.py can be found here: https://www.sbprojects.net/sbasm/
;
; board layout:
;   0 1 2
;   3 4 5
;   6 7 8
;

    .cr      6502
    .tf      ttt.hex, AP1, 8
    .or      $1000

echo         .eq     $ffef          ; sends the character in a to the console
prbyte       .eq     $ffdc          ; sends the value in a to the console in hex
exitapp      .eq     $ff1f          ; ends the app / returns to the Apple 1 monitor

; The Apple 1 reserves locations 0x0024 through 0x002b in the 0 page for the monitor.
; Put all globals in 0 page where it's faster because why not?

wpfunptr     .eq     $30            ; temporary spot for the function pointer pointer. occupies 30 and 31 in the 0-page
wpfunptrhigh .eq     $31
board        .eq     $32
board1       .eq     $33
board2       .eq     $34
board3       .eq     $35
board4       .eq     $36
board5       .eq     $37
board6       .eq     $38
board7       .eq     $39
board8       .eq     $3a
moves        .eq     $3b            ; # of moves examined so far
moveshigh    .eq     $3c
iters        .eq     $3d            ; # of iterations in the top-level loop
itershigh    .eq     $3e           
wpfun        .eq     $3f            ; temporary spot for the actual winner function pointer
wpfunhigh    .eq     $40
arg_move     .eq     $41            ; argument to min/max, but no need to be on stack
arg_depth    .eq     $42            ; same
local_score  .eq     $43            ; just a place to temporarily stash the score

max_score    .eq     9              ; maximum score
min_score    .eq     2              ; minimum score
win_score    .eq     6              ; winning score
tie_score    .eq     5              ; tie score
lose_score   .eq     4              ; losing score
XPIECE       .eq     1              ; X move piece
OPIECE       .eq     2              ; Y move piece
BLANKPIECE   .eq     0              ; empty piece
ITERATIONS   .eq     1000           ; loop this many times

start
    lda      #$0d                   ; every apple 1 app should go to the next line on the console
    jsr      echo
    lda      #$0a
    jsr      echo

    lda      #ITERATIONS
    sta      iters
    lda      /ITERATIONS
    sta      itershigh

    lda      #0                     ; clear the board
    sta      board
    sta      board1
    sta      board2
    sta      board3
    sta      board4
    sta      board5
    sta      board6
    sta      board7
    sta      board8

_again
    lda      #0                     ; reset moves each iteration or it will overflow
    sta      moves
    sta      movesHigh

    lda      #0                     ; first X move in position 0
    jsr      runmm
    lda      #1                     ; first X move in position 1
    jsr      runmm
    lda      #4                     ; first X move in position 4
    jsr      runmm

    lda      iters                                              ; loop to solve it again ITERATIONS times
    bne      _skip_iters_hi
    dec      itershigh
_skip_iters_hi
    dec      iters
    bne      _again
    lda      itershigh
    bne      _again

_done
    lda      movesHigh              ; display the # of moves examined
    jsr      prbyte
    lda      moves
    jsr      prbyte
    lda      #36                    ; print a $ to indicate the app is done. useful for measuring runtime.
    jsr      echo
    jmp      exitapp

; a has the offset into board where xpiece will take the first move

runmm
    pha                             ; save the move location
    tax                             ; save move location in x
    lda      #XPIECE
    sta      board, x               ; store the move on the board

    txa                             ; restore move location to a
    sta      arg_move               ; arg1: move
    lda      #0
    sta      arg_depth              ; arg2: depth
    lda      #max_score     
    pha                             ; arg3: beta
    lda      #min_score     
    pha                             ; arg4: alpha

    jsr      minmax_min             ; next move is O, so find the minimum score
    
    pla                             ; alpha
    pla                             ; beta

    pla                             ; restore move location
    tax                             ; move location in x
    lda      #BLANKPIECE
    sta      board, x               ; restore blank move to the board

    rts

minmax_arg_beta     .eq  $0106
minmax_arg_alpha    .eq  $0105
; gap of 2 for return address   ( 3 and 4 )
minmax_local_i      .eq  $0102
minmax_local_value  .eq  $0101
; return score in a

;
; Max
;

minmax_max
    inc      moves
    bne      _max_skip_moves_high
    inc      moveshigh
_max_skip_moves_high

    lda      arg_depth
    cmp      #4                     ; can't be a winner if < 4 moves so far
    bmi      _max_no_winner_check

    lda      arg_move               ; a has the proc to call 0..8
    ldx      #OPIECE                ; x has the most recent piece to move
    jsr      call_winnerproc

    cmp      #OPIECE                ; if O won, return loss
    bne      _max_no_winner_check
    lda      #lose_score            ; return a losing score since O won.
    rts

_max_no_winner_check
    lda      #$ff                   ; initialize local variables to 0xff
    pha                             ; allocate space for I
    pha                             ; allocate space for Value
    tsx                             ; put the current stack pointer in X to reference variables

    lda      #min_score             ; maximize for X's move
    sta      minmax_local_value, x

_max_loop                           ; for i = 0; i < 9; i++. i is initialized at function entry.
    inc      minmax_local_i, x      ; increment i
    lda      minmax_local_i, x
    cmp      #9
    beq      _max_load_value_return

    tay                             ; remember index i in y
    lda      board, y               ; load the current board position value. this sets the Z flag
    bne      _max_loop

    lda      #XPIECE
    sta      board, y               ; update the board with the move

    sty      arg_move
    inc      arg_depth              ; increment for recursion
    lda      minmax_arg_beta, x
    pha                             ; arg3: beta
    lda      minmax_arg_alpha, x
    pha                             ; arg4: alpha

    jsr      minmax_min             ; recurse
    sta      local_score            ; save the score

    dec      arg_depth              ; restore to pre-recursion
    pla                             ; alpha
    pla                             ; beta

    tsx                             ; restore x to the stack pointer location

    lda      minmax_local_i, x      ; load I
    tay                             ; save I in y for indexing
    lda      #BLANKPIECE
    sta      board, y               ; restore blank move to the board

    lda      local_score            ; load the score
    cmp      #win_score
    beq      _max_return_a          ; can't do better than winning

    cmp      minmax_local_value, x  ; compare score with value
    beq      _max_ab_prune          ; 6502 has no <= branch, and swapping args requires another load
    bmi      _max_ab_prune
    sta      minmax_local_value, x  ; update value with the better score

_max_ab_prune
    lda      minmax_local_value, x  ; load value
    cmp      minmax_arg_alpha, x    ; compare value with alpha
    beq      _max_check_beta        ; 6502 has no <= branch, and swapping args requires another load
    bmi      _max_check_beta
    sta      minmax_arg_alpha, x    ; update alpha with value

_max_check_beta
    lda      minmax_arg_alpha, x    ; load alpha
    cmp      minmax_arg_beta, x     ; compare alpha with beta
    bpl      _max_load_value_return ; beta pruning. bpl is >=
    jmp      _max_loop              ; loop for the next i
    
_max_return_a
    sta      minmax_local_value, x
_max_load_value_return
    ldy      minmax_local_value, x  ; load value for return
    pla                             ; deallocate value
    pla                             ; deallocate i
    tya                             ; score is in y
    rts                             ; return to sender

;
; Min
;

minmax_min
    inc      moves
    bne      _min_skip_moves_high
    inc      moveshigh
_min_skip_moves_high

    lda      arg_depth
    cmp      #4                     ; can't be a winner if < 4 moves so far
    bmi      _min_no_winner_check

    lda      arg_move               ; y has the proc to call 0..8
    ldx      #XPIECE                ; a has the most recent piece to move
    jsr      call_winnerproc

    cmp      #XPIECE                ; if X won, return win
    bne      _min_no_winner
    lda      #win_score
    rts

_min_no_winner
    lda      arg_depth
    cmp      #8                     ; the board is full
    bne      _min_no_winner_check   ; can't beq to return because it's too far away
    lda      #tie_score             ; cat's game
    rts

_min_no_winner_check
    lda      #$ff                   ; initialize local variables to ff
    pha                             ; allocate space for I
    pha                             ; allocate space for Value
    tsx                             ; put the current stack pointer in X to reference variables

    lda      #max_score             ; depth is even, so minimize for O's move
    sta      minmax_local_value, x

_min_loop                           ; for i = 0; i < 9; i++. i is initialized at function entry.
    inc      minmax_local_i, x      ; increment i
    lda      minmax_local_i, x
    cmp      #9
    beq      _min_load_value_return

    tay                             ; remember index i in y
    lda      board, y               ; load the current board position value. this sets the Z flag
    bne      _min_loop

    lda      #OPIECE
    sta      board, y               ; update the board with the move

    sty      arg_move
    inc      arg_depth              ; increment for recursion
    lda      minmax_arg_beta, x
    pha                             ; arg3: beta
    lda      minmax_arg_alpha, x
    pha                             ; arg4: alpha

    jsr      minmax_max             ; recurse
    sta      local_score            ; save the score

    dec      arg_depth
    pla                             ; alpha
    pla                             ; beta

    tsx                             ; restore x to the stack pointer location

    lda      minmax_local_i, x      ; load I
    tay                             ; save I in y for indexing
    lda      #BLANKPIECE
    sta      board, y               ; restore blank move to the board

    lda      local_score            ; load the score
    cmp      #lose_score
    beq      _min_return_a          ; can't do worse than a losing score

    cmp      minmax_local_value, x  ; compare score with value
    bpl      _min_ab_prune
    sta      minmax_local_value, x  ; update value with the better score

_min_ab_prune
    lda      minmax_local_value, x  ; load value
    cmp      minmax_arg_beta, x     ; compare value with beta
    bpl      _min_check_alpha
    sta      minmax_arg_beta, x     ; update beta with value

_min_check_alpha
    lda      minmax_arg_alpha, x    ; load alpha
    cmp      minmax_arg_beta, x     ; compare alpha with beta
    bpl      _min_load_value_return ; alpha pruning. bpl is >=
    jmp      _min_loop              ; loop for the next i
    
_min_return_a
    sta      minmax_local_value, x
_min_load_value_return
    ldy      minmax_local_value, x  ; load value for return
    pla                             ; deallocate value
    pla                             ; deallocate i
    tya                             ; score is in y
    rts                             ; return to sender

call_winnerproc
    ; A: the proc to call 0..8
    ; X: the piece last moved -- XPIECE or OPIECE

    ; store the proc to call in wpfun and wpfunhigh: proc0..proc8

    asl                             ; double the offset because each function pointer is 2 bytes
    clc                             ; clear the carry flag
    adc      #winnerprocs           ; add the low byte of the list of procs
    sta      wpfunptr               ; store the low byte of the pointer to the proc
    lda      #0
    adc      /winnerprocs           ; load the high byte with a carry if needed from the low bytes
    sta      wpfunptr+1             ; store the high byte of the pointer to the proc

    ldy      #0
    lda      (wpfunptr), y          ; read the low byte of the function pointer
    sta      wpfun                  ; write the low byte of the function pointer
    iny
    lda      (wpfunptr), y          ; read the high byte of the function pointer
    sta      wpfun+1                ; write the high byte of the function pointer

    txa                             ; put the piece to move in a xpiece or opiece
    jmp      (wpfun)                ; call it. (wpfun) will return to the caller of this function

proc0
    cmp      board1
    bne      _proc0_nextwin
    cmp      board2
    beq      _proc0_yes

_proc0_nextwin
    cmp      board3
    bne      _proc0_nextwin2
    cmp      board6
    beq      _proc0_yes

_proc0_nextwin2
    cmp      board4
    bne      _proc0_no
    cmp      board8
    beq      _proc0_yes

_proc0_no
    lda      #0

_proc0_yes
    rts

proc1
    cmp      board
    bne      _proc1_nextwin
    cmp      board2
    beq      _proc1_yes

_proc1_nextwin
    cmp      board4
    bne      _proc1_no
    cmp      board7
    beq      _proc1_yes

_proc1_no
    lda      #0

_proc1_yes
    rts

proc2
    cmp      board
    bne      _proc2_nextwin
    cmp      board1
    beq      _proc2_yes

_proc2_nextwin
    cmp      board5
    bne      _proc2_nextwin2
    cmp      board8
    beq      _proc2_yes

_proc2_nextwin2
    cmp      board4
    bne      _proc2_no
    cmp      board6
    beq      _proc2_yes

_proc2_no
    lda      #0

_proc2_yes
    rts

proc3
    cmp      board
    bne      _proc3_nextwin
    cmp      board6
    beq      _proc3_yes

_proc3_nextwin
    cmp      board4
    bne      _proc3_no
    cmp      board5
    beq      _proc3_yes

_proc3_no
    lda      #0

_proc3_yes
    rts

proc4
    cmp      board
    bne      _proc4_nextwin
    cmp      board8
    beq      _proc4_yes

_proc4_nextwin
    cmp      board2
    bne      _proc4_nextwin2
    cmp      board6
    beq      _proc4_yes

_proc4_nextwin2
    cmp      board1
    bne      _proc4_nextwin3
    cmp      board7
    beq      _proc4_yes

_proc4_nextwin3
    cmp      board3
    bne      _proc4_no
    cmp      board5
    beq      _proc4_yes

_proc4_no
    lda      #0

_proc4_yes
    rts

proc5
    cmp      board3
    bne      _proc5_nextwin
    cmp      board4
    beq      _proc5_yes

_proc5_nextwin
    cmp      board2
    bne      _proc5_no
    cmp      board8
    beq      _proc5_yes

_proc5_no
    lda      #0

_proc5_yes
    rts

proc6
    cmp      board4
    bne      _proc6_nextwin
    cmp      board2
    beq      _proc6_yes

_proc6_nextwin
    cmp      board
    bne      _proc6_nextwin2
    cmp      board3
    beq      _proc6_yes

_proc6_nextwin2
    cmp      board7
    bne      _proc6_no
    cmp      board8
    beq      _proc6_yes

_proc6_no
    lda      #0

_proc6_yes
    rts

proc7
    cmp      board1
    bne      _proc7_nextwin
    cmp      board4
    beq      _proc7_yes

_proc7_nextwin
    cmp      board6
    bne      _proc7_no
    cmp      board8
    beq      _proc7_yes

_proc7_no
    lda      #0

_proc7_yes
    rts

proc8
    cmp      board
    bne      _proc8_nextwin
    cmp      board4
    beq      _proc8_yes

_proc8_nextwin
    cmp      board2
    bne      _proc8_nextwin2
    cmp      board5
    beq      _proc8_yes

_proc8_nextwin2
    cmp      board6
    bne      _proc8_no
    cmp      board7
    beq      _proc8_yes

_proc8_no
    lda      #0

_proc8_yes
    rts

winnerprocs .dw   proc0, proc1, proc2, proc3, proc4, proc5, proc6, proc7, proc8

