# prove you can't win at tic-tac-tie.
# only solves for opening moves on 0, 1, and 4 because others are just reflect.ions
# 6493 board positions are evaluated per iteration across all 3 opening moves.
#
# boards positions:
#   0  1  2
#   3  4  5
#   6  7  8
#

import time
import threading
import multiprocessing

#from multiprocessing.pool import ThreadPool as Pool
from multiprocessing import freeze_support

evaluated = 0
iterations = 1000 # not 10k like other implementations because Python is too slow
piece_blank = 0
piece_x = 1
piece_o = 2

score_win = 6
score_tie = 5
score_lose = 4
score_max = 9
score_min = 2

def look_for_winner( board ):
    p = board[ 0 ]
    if piece_blank != p:
        if p == board[1] and p == board[2]:
            return p
        if p == board[3] and p == board[6]:
            return p

    p = board[3]
    if piece_blank != p and p == board[4] and p == board[5]:
        return p

    p = board[6]
    if piece_blank != p and p == board[7] and p == board[8]:
        return p

    p = board[1]
    if piece_blank != p and p == board[4] and p == board[7]:
        return p

    p = board[2]
    if piece_blank != p and p == board[5] and p == board[8]:
        return p

    p = board[4]
    if piece_blank != p:
        if p == board[0] and p == board[8]:
            return p
        if p == board[2] and p == board[6]:
            return p

    return piece_blank

def pos0func( b ):
    p = b[0]
    if ( ( p == b[1] and p == b[2] ) or
         ( p == b[3] and p == b[6] ) or
         ( p == b[4] and p == b[8] ) ):
         return p
    return piece_blank

def pos1func( b ):
    p = b[1]
    if ( ( p == b[0] and p == b[2] ) or
         ( p == b[4] and p == b[7] ) ):
         return p
    return piece_blank

def pos2func( b ):
    p = b[2]
    if ( ( p == b[0] and p == b[1] ) or
         ( p == b[5] and p == b[8] ) or
         ( p == b[4] and p == b[6] ) ):
         return p
    return piece_blank

def pos3func( b ):
    p = b[3]
    if ( ( p == b[4] and p == b[5] ) or
         ( p == b[0] and p == b[6] ) ):
         return p
    return piece_blank

def pos4func( b ):
    p = b[4]
    if ( ( p == b[0] and p == b[8] ) or
         ( p == b[2] and p == b[6] ) or
         ( p == b[1] and p == b[7] ) or
         ( p == b[3] and p == b[5] ) ):
         return p
    return piece_blank

def pos5func( b ):
    p = b[5]
    if ( ( p == b[3] and p == b[4] ) or
         ( p == b[2] and p == b[8] ) ):
         return p
    return piece_blank

def pos6func( b ):
    p = b[6]
    if ( ( p == b[7] and p == b[8] ) or
         ( p == b[0] and p == b[3] ) or
         ( p == b[4] and p == b[2] ) ):
         return p
    return piece_blank

def pos7func( b ):
    p = b[7]
    if ( ( p == b[6] and p == b[8] ) or
         ( p == b[1] and p == b[4] ) ):
         return p
    return piece_blank

def pos8func( b ):
    p = b[8]
    if ( ( p == b[6] and p == b[7] ) or
         ( p == b[2] and p == b[5] ) or
         ( p == b[0] and p == b[4] ) ):
         return p
    return piece_blank

move_functions = [ pos0func, pos1func, pos2func, pos3func, pos4func, pos5func, pos6func, pos7func, pos8func ]

def min_max( board, alpha, beta, depth, move ):
    # just for debugging; total moves should be multiple of 6493 for 3 starting positions
    #global evaluated
    #evaluated += 1

    if depth >= 4:

        # function pointers are about 20% faster than look_for_winner
        #p = look_for_winner( board )
        p = move_functions[ move ]( board )

        if ( piece_blank != p ):
            if piece_x == p:
                return score_win

            return score_lose

        if 8 == depth:
            return score_tie

    if 0 != ( depth & 1 ):
        value = score_min
        pieceMove = piece_x
    else:
        value = score_max
        pieceMove = piece_o

    for x in range( 0, 9 ):
        if piece_blank == board[ x ]:
            board[ x ] = pieceMove
            score = min_max( board, alpha, beta, depth + 1, x )
            board[ x ] = piece_blank

            if 0 != ( depth & 1 ):
                if score_win == score:
                    return score_win
                if score > value:
                    value = score
                if value > alpha:
                    alpha = value
                if alpha >= beta:
                    return value
            else:
                if score_lose == score:
                    return score_lose
                if score < value:
                    value = score
                if value < beta:
                    beta = value
                if beta <= alpha:
                    return value
    return value

def run_board( move ):
    b = [ 0, 0, 0, 0, 0, 0, 0, 0, 0 ]
    b[ move ] = piece_x
    #print( f"run_board for " + str( move ) )

    for i in range( 0, iterations ):
        score = min_max( b, score_min, score_max, 0, move )
        #if score_tie != score:
        #    print( f"didn't get a tie score!")

def run_app():
    global evaluated
    serial_start_time = time.time()

    run_board( 0 )
    run_board( 1 )
    run_board( 4 )

    serial_end_time = time.time()
    serial_time = serial_end_time - serial_start_time
    serial_evaluated = evaluated

    evaluated = 0
    parallel_start_time = time.time()

    # using multipule threads doesn't help because they all share 1 core
    #pool = Pool()
    #pool.apply_async( run_board, ( 0, ) )
    #pool.apply_async( run_board, ( 1, ) )
    #pool.apply_async( run_board, ( 4, ) )
    #pool.close()
    #pool.join()

    p0 = multiprocessing.Process( target = run_board, args = ( 0, ) )
    p1 = multiprocessing.Process( target = run_board, args = ( 1, ) )
    p4 = multiprocessing.Process( target = run_board, args = ( 4, ) )

    p0.start()
    p1.start()
    p4.start()

    p0.join()
    p1.join()
    p4.join()

    parallel_end_time = time.time()
    parallel_time = parallel_end_time - parallel_start_time

    # this will be 0 when using multiprocessing because the variable isn't marshalled back
    parallel_evaluated = evaluated

    print( f"serial moves evaluated: " + str( serial_evaluated ) )
    print( f"    elapsed time:  " + str( serial_time ) + " seconds" )
    print( f"    one iteration: " + str( ( serial_time ) / iterations * 1000 ) + " ms" )
    print( f"parallel moves evaluated: " + str( parallel_evaluated ) )
    print( f"    elapsed time:  " + str( parallel_time ) + " seconds" )
    print( f"    one iteration: " + str( ( parallel_time ) / iterations * 1000 ) + " ms" )

if __name__ == '__main__':
    freeze_support()   # needed to run on Mac (not Windows or WSL)
    run_app()
