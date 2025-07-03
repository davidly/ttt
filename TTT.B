// bcpl version of app to prove you can't win at tic-tac-toe if the opponent is competent.
// should result in 6493 board positions examined.

GET "LIBHDR"

MANIFEST
$(
    scoreWin = 6
    scoreTie = 5
    scoreLose = 4
    scoreMax = 9
    scoreMin = 2
    scoreInvalid = 0

    pieceBlank = 0
    pieceX = 1
    pieceO = 2

    iterations = 10
$)

STATIC
$(
    movecount = 0
    board = ?
$)

LET START() BE
$(
    LET i = ?
    board := getvec( 9 )

    FOR i = 0 TO 8 DO board!i := 0

    FOR i = 1 TO iterations DO
    $(
        movecount := 0
        runit( 0 )
        runit( 1 )
        runit( 4 )
    $)

    WRITEF( "%N moves*N", movecount )
$)

AND winner2( move ) = VALOF
$(
    LET x = board!move

    SWITCHON move INTO
    $(
        CASE 0 :
            IF ( ( ( x EQ board!1 ) & ( x EQ board!2 ) ) |
                 ( ( x EQ board!3 ) & ( x EQ board!6 ) ) |
                 ( ( x EQ board!4 ) & ( x EQ board!8 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 1 :
            IF ( ( ( x EQ board!0 ) & ( x EQ board!2 ) ) |
                 ( ( x EQ board!4 ) & ( x EQ board!7 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 2 :
            IF ( ( ( x EQ board!0 ) & ( x EQ board!1 ) ) |
                 ( ( x EQ board!5 ) & ( x EQ board!8 ) ) |
                 ( ( x EQ board!4 ) & ( x EQ board!6 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 3 :
            IF ( ( ( x EQ board!4 ) & ( x EQ board!5 ) ) |
                 ( ( x EQ board!0 ) & ( x EQ board!6 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 4 :
            IF ( ( ( x EQ board!0 ) & ( x EQ board!8 ) ) |
                 ( ( x EQ board!2 ) & ( x EQ board!6 ) ) |
                 ( ( x EQ board!1 ) & ( x EQ board!7 ) ) |
                 ( ( x EQ board!3 ) & ( x EQ board!5 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 5 :
            IF ( ( ( x EQ board!3 ) & ( x EQ board!4 ) ) |
                 ( ( x EQ board!2 ) & ( x EQ board!8 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 6 :
            IF ( ( ( x EQ board!7 ) & ( x EQ board!8 ) ) |
                 ( ( x EQ board!0 ) & ( x EQ board!3 ) ) |
                 ( ( x EQ board!4 ) & ( x EQ board!2 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 7 :
            IF ( ( ( x EQ board!6 ) & ( x EQ board!8 ) ) |
                 ( ( x EQ board!1 ) & ( x EQ board!4 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
        CASE 8 :
            IF ( ( ( x EQ board!6 ) & ( x EQ board!7 ) ) |
                 ( ( x EQ board!2 ) & ( x EQ board!5 ) ) |
                 ( ( x EQ board!0 ) & ( x EQ board!4 ) ) )
                THEN RESULTIS x
            RESULTIS pieceBlank
    $)

    RESULTIS pieceBlank
$)

AND minmax( alpha, beta, depth, move ) = VALOF
$(
    LET p = ?
    LET value = scoreTie
    LET pieceMove = ?
    LET score = ?

    //WRITEF( "moves, depth, move %N, %N, %N  ", movecount, depth, move )
    //WRITEF( "  %N%N%N%N%N%N%N%N%N*N", board!0, board!1, board!2, board!3, board!4, board!5, board!6, board!7, board!8 )

    movecount := movecount + 1
    IF depth >= 4 THEN
    $(
        p := winner2( move )
        IF p NE pieceBlank DO
        $(
            IF p EQ pieceX THEN RESULTIS scoreWin

            RESULTIS scoreLose
        $)

        IF DEPTH EQ 8 THEN RESULTIS scoreTie
    $)

    TEST ( depth & 1 ) EQ 1 DO
    $(
        value := scoreMin
        pieceMove := pieceX
    $)
    ELSE
    $(
        value := scoreMax
        pieceMove := pieceO
    $)
    
    FOR p = 0 TO 8 DO
    $(
        IF pieceBlank EQ board!p THEN
        $(
            board!p := pieceMove
            score := minmax( alpha, beta, depth + 1, p )
            board!p := pieceBlank

            TEST pieceMove EQ pieceX DO
            $(
                IF score > value THEN
                $(
                    value := score
                    IF ( ( value EQ scoreWin ) | ( value >= beta ) ) THEN BREAK
                    IF value > alpha THEN alpha := value
                $)
            $)
            ELSE
            $(
                IF score < value THEN
                $(
                    value := score
                    IF ( ( value EQ scoreLose ) | ( value <= alpha ) ) THEN BREAK
                    IF value < beta THEN beta := value
                $)
            $)
        $)
    $)

    RESULTIS value
$)

AND runit( move ) BE
$(
    board!move := pieceX
    minmax( scoreMin, scoreMax, 0, move )
    board!move := pieceBlank
$)

.

