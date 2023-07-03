package main

//
// Prove there can be no winner in tic tac toe.
// board:
//   0 1 2
//   3 4 5
//   6 7 8
//

import (
    "fmt"
    //"sync/atomic"
    "time"
)

var evaluated int64

type WinFunc func( board [9] int ) int

const (
    SCORE_WIN = 6
    SCORE_TIE = 5
    SCORE_LOSE = 4
    SCORE_MAX = 9
    SCORE_MIN = 2

    PIECE_BLANK = 0
    PIECE_X = 1
    PIECE_O = 2

    Iterations = 10000
)

// I validated max and min are inlined by the compiler

func max( x, y int ) int {
    if x < y {
        return y
    }

    return x
}

func min( x, y int ) int {
    if x < y {
        return x
    }

    return y
}

func pos0func( board [9] int ) int {
    x := board[ 0 ]

    if ( ( x == board[1] && x == board[2] ) ||
         ( x == board[3] && x == board[6] ) ||
         ( x == board[4] && x == board[8] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos1func( board [9] int ) int {
    x := board[ 1 ]

    if ( ( x == board[0] && x == board[2] ) ||
         ( x == board[4] && x == board[7] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos2func( board [9] int ) int {
    x := board[ 2 ]

    if ( ( x == board[0] && x == board[1] ) ||
         ( x == board[5] && x == board[8] ) ||
         ( x == board[4] && x == board[6] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos3func( board [9] int ) int {
    x := board[ 3 ]

    if ( ( x == board[4] && x == board[5] ) ||
         ( x == board[0] && x == board[6] ) )  {
        return x
    }

    return PIECE_BLANK
}

func pos4func( board [9] int ) int {
    x := board[ 4 ]

    if ( ( x == board[0] && x == board[8] ) ||
         ( x == board[2] && x == board[6] ) ||
         ( x == board[1] && x == board[7] ) ||
         ( x == board[3] && x == board[5] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos5func( board [9] int ) int {
    x := board[ 5 ]

    if ( ( x == board[3] && x == board[4] ) ||
         ( x == board[2] && x == board[8] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos6func( board [9] int ) int {
    x := board[ 6 ]

    if ( ( x == board[7] && x == board[8] ) ||
         ( x == board[0] && x == board[3] ) ||
         ( x == board[4] && x == board[2] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos7func( board [9] int ) int {
    x := board[ 7 ]

    if ( ( x == board[6] && x == board[8] ) ||
         ( x == board[1] && x == board[4] ) ) {
        return x
    }

    return PIECE_BLANK
}

func pos8func( board [9] int ) int {
    x := board[ 8 ]

    if ( ( x == board[6] && x == board[7] ) ||
         ( x == board[2] && x == board[5] ) ||
         ( x == board[0] && x == board[4] ) ) {
        return x
    }

    return PIECE_BLANK
}

var winner_functions[9] WinFunc = [9] WinFunc {
    pos0func,
    pos1func,
    pos2func,
    pos3func,
    pos4func,
    pos5func,
    pos6func,
    pos7func,
    pos8func }

func dump_board( board [9] int ) {
    fmt.Printf( "{" );

    for i := 0; i < 9; i++ {
        fmt.Printf( "%v", board[i] )
    }

    fmt.Printf( "}" );
}  

func lookforwinner( board [9] int ) int {
    p := board[ 0 ]
    if PIECE_BLANK != p {
        if p == board[ 1 ] && p == board[ 2 ] {
            return p
        }
        if p == board[ 3 ] && p == board[ 6 ] {
            return p
        }
    }

    p = board[ 1 ]
    if PIECE_BLANK != p && p == board[ 4 ] && p == board[ 7 ] {
        return p
    }

    p = board[ 2 ]
    if PIECE_BLANK != p && p == board[ 5 ] && p == board[ 8 ] {
        return p
    }

    p = board[ 3 ]
    if PIECE_BLANK != p && p == board[ 4 ] && p == board[ 5 ] {
        return p
    }

    p = board[ 6 ]
    if PIECE_BLANK != p && p == board[ 7 ] && p == board[ 8 ] {
        return p
    }

    p = board[ 4 ]
    if PIECE_BLANK != p {
        if p == board[ 0 ] && p == board[ 8 ] {
            return p
        }

        if p == board[ 2 ] && p == board[ 6 ] {
            return p
        }
    }

    return PIECE_BLANK
}

func minmax( board [9] int, alpha int, beta int, depth int, move int ) int {
    // keeping track of the # of moves is very slow, especially with concurrency
    // so only do this when debugging or validating.
    //atomic.AddInt64( &evaluated, 1 )
    //evaluated++

    if depth >= 4 {
        // Slightly faster with winner_functions

        //p := lookforwinner( board )
        p := winner_functions[ move ]( board )

        if ( PIECE_BLANK != p ) {
            if p == PIECE_X {
                return SCORE_WIN
            }

            return SCORE_LOSE
        }

        if 8 == depth {
            return SCORE_TIE
        }
    }

    maximize := 0 != ( depth & 1 )
    var value, pieceMove int

    if maximize {
        value = SCORE_MIN
        pieceMove = PIECE_X
    } else {
        value = SCORE_MAX
        pieceMove = PIECE_O
    }

    for i := 0; i < 9; i++ {
        if PIECE_BLANK == board[ i ] {
            board[ i ] = pieceMove

            score := minmax( board, alpha, beta, depth + 1, i )

            board[ i ] = PIECE_BLANK

            if maximize {
                if ( SCORE_WIN == score ) {
                    return SCORE_WIN;
                }

                if ( score > value ) {
                    value = score;

                    if ( value >= beta ) {
                        return value;
                    }
                    if ( value > alpha ) {
                        alpha = value;
                    }
    
                }
            } else {
                if ( SCORE_LOSE == score ) {
                    return SCORE_LOSE;
                }

                if ( score < value ) {
                    value = score;

                    if ( value <= alpha ) {
                        return value;
                    }
                    if ( value < beta ) {
                        beta = value;
                    }
                }
            }
        }
    }

    return value
}

func runboard( position int ) int {
    board := [9] int { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    score := 0
    board[ position ] = PIECE_X

    for l := 0; l < Iterations; l++ {
        score = minmax( board, SCORE_MIN, SCORE_MAX, 0, position )
    }

    return score
}

func runboardchan( position int ) <- chan int {
    c := make( chan int )

    go func() {
        c <- runboard( position )
    }()

    return c
}

func main() {

/*
    // for testing...

    board := [9] int { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    board[0] = PIECE_X
    score := minmax( board, SCORE_MIN, SCORE_MAX, 0, 0 )
    fmt.Printf( "score: %v, moves evaluted %v\n", score, evaluated )
    board[0] = PIECE_BLANK
    board[1] = PIECE_X
    score = minmax( board, SCORE_MIN, SCORE_MAX, 0, 1 )
    fmt.Printf( "score: %v, moves evaluted %v\n", score, evaluated )
    board[1] = PIECE_BLANK
    board[4] = PIECE_X
    score = minmax( board, SCORE_MIN, SCORE_MAX, 0, 4 )
    board[4] = PIECE_BLANK
    fmt.Printf( "score: %v, moves evaluted %v\n", score, evaluated )
    evaluated = 0;
*/

    // Only check 3 starting moves because others are just reflections

    start := time.Now()

    sx := runboard( 0 )
    sy := runboard( 1 )
    sz := runboard( 4 )

    serialDuration := time.Since( start )
    //serialEvaluated := evaluated
    evaluated = 0

    start = time.Now()

    cx := runboardchan( 0 )
    cy := runboardchan( 1 )
    cz := runboardchan( 4 )

    x := <- cx
    y := <- cy
    z := <- cz

    parallelDuration := time.Since( start )

    fmt.Printf( "ran %v iterations\n", Iterations );
    fmt.Printf( "serial duration in ms %f\n", float64( serialDuration.Nanoseconds() ) / 1000000.0 )
    fmt.Printf( "  serial scores for a, b, c %v %v %v\n", sx, sy, sz )
    fmt.Printf( "parallel duration in ms %f\n", float64( parallelDuration.Nanoseconds() ) / 1000000.0 )
    fmt.Printf( "  parallel scores for x, y, z %v %v %v\n", x, y, z )
    //fmt.Printf( "complete! moves evaluated serial %v, parallel %v\n", serialEvaluated, evaluated )
}
