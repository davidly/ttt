;
; Apple 1 / 6502 implementation of proving you can't win at tic-tac-toe.
; Takes about 3 seconds to run each iteration of 3 unique starting moves.
; That's on an Apple 1 replica.
; Given 10 iterations, that's about 30 seconds.
; The moves variable should contain 6493 decimal / 0x195d hex if it's running correctly.
; On the Pom1 Apple 1 simulator it takes 2 seconds per iteration. Not sure why.
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
    .tf      ttt.h, AP1, 8
    .or      $1000

echo         .eq     $ffef
prbyte       .eq     $ffdc
exitapp      .eq     $ff1f

max_score    .eq     9              ; maximum score
min_score    .eq     2              ; minimum score
win_score    .eq     6              ; winning score
tie_score    .eq     5              ; tie score
lose_score   .eq     4              ; losing score
XPIECE       .eq     1              ; X move piece
OPIECE       .eq     2              ; Y move piece
BLANKPIECE   .eq     0              ; empty piece
ITERATIONS   .eq     10             ; loop this many times

start
    lda      #$0d                   ; every apple 1 app should go to the next line
    jsr      echo
    lda      #$0a
    jsr      echo

    lda      #ITERATIONS
    sta      iters                  

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

    dec      iters
    bne      _again                 ; loop while not 0

_done
    lda      movesHigh              ; display the # of moves examined
    jsr      prbyte
    lda      moves
    jsr      prbyte
    lda      #36                    ; print a $ to indicate the app is done
    jsr      echo
    jmp      exitapp

; a has the offset into board where xpiece will take the first move

runmm
    pha                             ; save the move location
    tax                             ; save move location in x
    lda      #XPIECE
    sta      board, x               ; store the move on the board

    txa                             ; restore move location to a
    pha                             ; arg1: the move location 0-8
    lda      #0             
    pha                             ; arg2: depth
    lda      #max_score     
    pha                             ; arg3: beta
    lda      #min_score     
    pha                             ; arg4: alpha

    jsr      minmax
    
    pla                             ; alpha
    pla                             ; beta
    pla                             ; depth
    pla                             ; move

    pla                             ; restore move location
    tax                             ; move location in x
    lda      #BLANKPIECE
    sta      board, x               ; restore blank move to the board

    rts

minmax_arg_move     .eq  $010a
minmax_arg_depth    .eq  $0109
minmax_arg_beta     .eq  $0108
minmax_arg_alpha    .eq  $0107
; gap of 2 for return address   ( 5 and 6 )
minmax_local_pm     .eq  $0104
minmax_local_i      .eq  $0103
minmax_local_score  .eq  $0102
minmax_local_value  .eq  $0101
; return score in a

minmax
    lda      #0
    pha                             ; allocate space for Player Move
    pha                             ; allocate space for I
    pha                             ; allocate space for Score
    pha                             ; allocate space for Value

    tsx                             ; put the current stack pointer in X to reference variables

    inc      moves
    bne      _skip_moves_high
    inc      moveshigh
_skip_moves_high

; debug code
;    lda      minmax_arg_depth, x
;    clc
;    adc      #70                    ; 70 is F
;    jsr      echo
;    tsx                             ; put the current stack pointer in X to reference variables

;    lda      minmax_arg_move, x
;    clc
;    adc      #80                    ; 80 is P
;    jsr      echo                                            
;    tsx                             ; put the current stack pointer in X to reference variables
;
;    lda      minmax_arg_alpha, x
;    clc
;    adc      #48
;    jsr      echo
;    tsx                             ; put the current stack pointer in X to reference variables
;
;    lda      minmax_arg_beta, x
;    clc
;    adc      #48
;    jsr      echo
;    tsx                             ; put the current stack pointer in X to reference variables
; end debug code

    lda      minmax_arg_depth, x
    cmp      #4                     ; can't be a winner if < 4 moves so far
    bmi      _no_winner_check

    jsr      winner
    tsx                             ; restore x with sp in case winner changed it with debugging code

    cmp      #BLANKPIECE            ; did either piece win?
    beq      _no_winner

    cmp      #XPIECE                ; if X won, return win
    bne      _o_winner
    ldy      #win_score
    jmp      _load_y_return

_o_winner
    ldy      #lose_score            ; return a losing score since O won.
    jmp      _load_y_return

_no_winner
    lda      minmax_arg_depth, x
    cmp      #8                     ; the board is full
    bne      _no_winner_check       ; can't beq to return because it's too far away
    ldy      #tie_score             ; potentially wasted load
    jmp      _load_y_return         ; cat's game

_no_winner_check
    lda      minmax_arg_depth, x
    and      #1                     ; is the depth odd or even?
    beq      _minimize_setup

    lda      #min_score             ; it's odd, so maximize for X's move
    sta      minmax_local_value, x
    lda      #XPIECE
    sta      minmax_local_pm, x
    jmp      _loop

_minimize_setup
    lda      #max_score             ; depth is even, so minimize for O's move
    sta      minmax_local_value, x
    lda      #OPIECE
    sta      minmax_local_pm, x

_loop                               ; for i = 0; i < 0; i++
    lda      minmax_local_i, x
    cmp      #9
    bne      _loop_keep_going       ; can't beq to return because it's too far awawy
    jmp      _load_value_return

_loop_keep_going
    tay                             ; remember index i in y
    lda      board, y               ; load the current board position value
    cmp      #0                     ; is the board position free?
    beq      _position_available
    jmp      _next_i

_position_available
    lda      minmax_local_pm, x     ; load the current player move ( X or O )
    sta      board, y               ; update the board with the move

    tya
    pha                             ; arg1: the move
    lda      minmax_arg_depth, x
    clc
    adc      #1
    pha                             ; arg2: the depth ( current + 1 )
    lda      minmax_arg_beta, x
    pha                             ; arg3: beta
    lda      minmax_arg_alpha, x
    pha                             ; arg4: alpha

    jsr      minmax                 ; recurse
    tay                             ; save result in y
    
    pla                             ; alpha
    pla                             ; beta
    pla                             ; depth
    pla                             ; move

    tsx                             ; restore x to the stack pointer location
    tya                             ; restore minmax result to a
    sta      minmax_local_score, x  ; update score with the result

    lda      minmax_local_i, x      ; load I
    tay                             ; save I in y for indexing
    lda      #BLANKPIECE
    sta      board, y               ; restore blank move to the board

    lda      minmax_arg_depth, x    ; is the depth odd or even (maximize or minimize)?
    and      #1
    beq      _minimize_score

_maximize_score
    lda      minmax_local_score, x  ; load the score
    cmp      #win_score
    bne      _max_keep_going        ; can't beq to return because it's too far away
    tay
    jmp      _load_y_return         ; can't do better than win; return now

_max_keep_going
    cmp      minmax_local_value, x  ; compare score with value
    beq      _max_ab_prune
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
    bmi      _next_i
    jmp      _load_value_return     ; beta pruning

_minimize_score
    lda      minmax_local_score, x  ; load the score
    cmp      #lose_score
    bne      _min_keep_going
    tay
    jmp      _load_y_return         ; can't do worse than lose; return now

_min_keep_going
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
    bmi      _next_i                ; 
_min_prune
    jmp      _load_value_return     ; alpha pruning

_next_i
    inc      minmax_local_i, x      ; increment i
    jmp      _loop                  ; loop for the next i
    
_load_value_return
    lda      minmax_local_value, x  ; load value for return
    tay
_load_y_return
    pla                             ; deallocate pm
    pla                             ; deallocate i
    pla                             ; deallocate score
    pla                             ; deallocate value
    tya                             ; score is in y
    rts                             ; return to sender

; return winning piece in a or 0 if a tie

winner
    lda      board
    cmp      #0
    beq      _win_check_3

    cmp      board1
    bne      _win_check_0_b
    cmp      board2
    bne      _win_check_0_b
    rts

_win_check_0_b
    cmp      board3
    bne      _win_check_3
    cmp      board6
    bne      _win_check_3
    rts

_win_check_3
    lda      board3
    cmp      #0
    beq      _win_check_6

    cmp      board4
    bne      _win_check_6
    cmp      board5
    bne      _win_check_6
    rts

_win_check_6
    lda      board6
    cmp      #0
    beq      _win_check_1

    cmp      board7
    bne      _win_check_1
    cmp      board8
    bne      _win_check_1
    rts

_win_check_1
    lda      board1
    cmp      #0
    beq      _win_check_2

    cmp      board4
    bne      _win_check_2
    cmp      board7
    bne      _win_check_2
    rts

_win_check_2
    lda      board2
    cmp      #0
    beq      _win_check_4

    cmp      board5
    bne      _win_check_4
    cmp      board8
    bne      _win_check_4
    rts

_win_check_4
    lda      board4
    cmp      #0
    beq      _win_return

    cmp      board
    bne      _win_check_4_b
    cmp      board8
    bne      _win_check_4_b
    rts

_win_check_4_b
    cmp      board2
    bne      _win_return_blank
    cmp      board6
    beq     _win_return

_win_return_blank
    lda      #0

_win_return
    rts

board     .db     0
board1    .db     0
board2    .db     0
board3    .db     0
board4    .db     0
board5    .db     0
board6    .db     0
board7    .db     0
board8    .db     0
moves     .db     0
moveshigh .db     0
iters     .db     0


