//
//  main.swift
//  sttt
//
//  Created by David Lee on 1/30/21.
//

import Foundation

let SCORE_WIN = 6
let SCORE_TIE = 5
let SCORE_LOSE = 4
let SCORE_MAX = 9
let SCORE_MIN = 2
var g_moves = 0

enum Piece : UInt8 { case blank=0, X, O }

func winner_proc0(b : Board) -> Piece
{
    let x = b.board[0];
    
    if ( ( x == b.board[1] && x == b.board[2] ) ||
         ( x == b.board[3] && x == b.board[6] ) ||
         ( x == b.board[4] && x == b.board[8] ) )
        { return x }
    
    return Piece.blank
}

func winner_proc1(b : Board) -> Piece
{
    let x = b.board[1];
    
    if ( ( x == b.board[0] && x == b.board[2] ) ||
         ( x == b.board[4] && x == b.board[7] ) )
        { return x }
    
    return Piece.blank
}

func winner_proc2(b : Board) -> Piece
{
    let x = b.board[2];
    
    if ( ( x == b.board[0] && x == b.board[1] ) ||
         ( x == b.board[4] && x == b.board[6] ) ||
         ( x == b.board[5] && x == b.board[8] ) )
        { return x }
    
    return Piece.blank
}
func winner_proc3(b : Board) -> Piece
{
    let x = b.board[3];
    
    if ( ( x == b.board[0] && x == b.board[6] ) ||
         ( x == b.board[4] && x == b.board[5] ) )
        { return x }
    
    return Piece.blank
}
func winner_proc4(b : Board) -> Piece
{
    let x = b.board[4];
    
    if ( ( x == b.board[0] && x == b.board[8] ) ||
         ( x == b.board[2] && x == b.board[6] ) ||
         ( x == b.board[1] && x == b.board[7] ) ||
         ( x == b.board[3] && x == b.board[5] ) )
        { return x }
    
    return Piece.blank
}
func winner_proc5(b : Board) -> Piece
{
    let x = b.board[5];
    
    if ( ( x == b.board[2] && x == b.board[8] ) ||
         ( x == b.board[3] && x == b.board[4] ) )
        { return x }
    
    return Piece.blank
}
func winner_proc6(b : Board) -> Piece
{
    let x = b.board[6];
    
    if ( ( x == b.board[0] && x == b.board[3] ) ||
         ( x == b.board[2] && x == b.board[4] ) ||
         ( x == b.board[7] && x == b.board[8] ) )
        { return x }
    
    return Piece.blank
}
func winner_proc7(b : Board) -> Piece
{
    let x = b.board[7];
    
    if ( ( x == b.board[1] && x == b.board[4] ) ||
         ( x == b.board[6] && x == b.board[8] ) )
        { return x }
    
    return Piece.blank
}

func winner_proc8(b : Board) -> Piece
{
    let x = b.board[8];
    
    if ( ( x == b.board[2] && x == b.board[5] ) ||
         ( x == b.board[6] && x == b.board[7] ) ||
         ( x == b.board[0] && x == b.board[4] ) )
        { return x }
    
    return Piece.blank
}

var winner_funcs: Array<(Board) -> Piece> =
[
    winner_proc0,
    winner_proc1,
    winner_proc2,
    winner_proc3,
    winner_proc4,
    winner_proc5,
    winner_proc6,
    winner_proc7,
    winner_proc8
]

class Board
{
    var board: [Piece] = [ Piece.blank, Piece.blank, Piece.blank,
                           Piece.blank, Piece.blank, Piece.blank,
                           Piece.blank, Piece.blank, Piece.blank ]
    func Print() -> Void
    {
        print( board[0], board[1], board[2],
               board[3], board[4], board[5],
               board[6], board[7], board[8] )
    }
    
    func LookForWinner() -> Piece
    {
        var p = board[0]
        if ( Piece.blank != p)
        {
            if ( p == board[1] && p == board[2] ) { return p }
            if ( p == board[3] && p == board[6] ) { return p }
        }
        
        p = board[3]
        if ( Piece.blank != p && p == board[4] && p == board[5]) { return p }

        p = board[6]
        if ( Piece.blank != p && p == board[7] && p == board[8]) { return p }

        p = board[1]
        if ( Piece.blank != p && p == board[4] && p == board[7]) { return p }

        p = board[2]
        if ( Piece.blank != p && p == board[5] && p == board[8]) { return p }

        p = board[4]
        if ( Piece.blank != p)
        {
            if ( p == board[0] && p == board[8] ) { return p }
            if ( p == board[2] && p == board[6] ) { return p }
        }
    
        return Piece.blank
    }
}

func Max( x : Int, y : Int) -> Int
{
    if ( x > y) { return x }
    return y
}

func Min( x: Int, y : Int) -> Int
{
    if ( x < y ) { return x }
    return y
}

func MinMax( b : Board, alpha : Int, beta : Int, depth : Int, pos : Int) -> Int
{
    //print( " alpha ", alpha, " beta ", beta, " depth ", depth )
    //b.Print()
    
    g_moves += 1
    
    if ( depth >= 4 )
    {
        // The function table is SLOWER in Swift (2.7 vs 2.2 seconds); significantly faster in C++
        //let p2 : Piece = winner_funcs[ pos ](b)
        let p : Piece = b.LookForWinner()
        /*
        if ( p2 != p)
        {
            print( "p ", p, " p2 ", p2, " pos ", pos)
            b.Print()
            exit(1)
        }
        */
        
        if ( Piece.X == p) { return SCORE_WIN }
        if ( Piece.O == p) { return SCORE_LOSE }
        if ( 8 == depth ) { return SCORE_TIE }
    }
    
    var localAlpha = alpha
    var localBeta = beta
    
    var value : Int
    var pieceMove : Piece
    
    if ( 0 != ( depth & 1 ) )
    {
        value = SCORE_MIN
        pieceMove = Piece.X
    }
    else
    {
        value = SCORE_MAX
        pieceMove = Piece.O
    }
    
    for x in 0...8
    {
        if ( Piece.blank == b.board[x])
        {
            b.board[x] = pieceMove
            let score = MinMax( b: b, alpha: localAlpha, beta: localBeta, depth: depth + 1, pos: x )
            b.board[x] = Piece.blank
            
            if ( 0 != ( depth & 1 ) )
            {
                value = Max( x: value, y: score )
                localAlpha = Max( x: localAlpha, y: value )
                if ( localAlpha >= localBeta ) { return value } // alpha pruning
                if ( SCORE_WIN == value) { return SCORE_WIN }
            }
            else
            {
                value = Min( x: value, y: score )
                localBeta = Min( x: value, y: localBeta )
                if ( localBeta <= localAlpha ) { return value } // beta pruning
                if ( SCORE_LOSE == value) { return SCORE_LOSE }
            }
        }
    }
    
    return value
}

func main()
{
    let b1 = Board()
    b1.board[0] = Piece.X
    let b2 = Board()
    b2.board[1] = Piece.X
    let b3 = Board()
    b3.board[4] = Piece.X
    var score1 = 0
    var score2 = 0
    var score3 = 0

    for _ in 1...10000
    {
        score1 = MinMax( b: b1, alpha: SCORE_MIN, beta: SCORE_MAX, depth: 0, pos: 0)
        score2 = MinMax( b: b2, alpha: SCORE_MIN, beta: SCORE_MAX, depth: 0, pos: 1)
        score3 = MinMax( b: b3, alpha: SCORE_MIN, beta: SCORE_MAX, depth: 0, pos: 4)
    }

    print("moves: ", g_moves, " scores: ", score1, score2, score3)
}

main()

