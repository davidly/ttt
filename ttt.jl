#
# Julia app to determine nuclear war can't be won
#
# board layout:
#   1 2 3
#   3 5 6
#   7 8 9
#

import Base.Threads.@threads
using Base.Threads

global evaluated = 0
iterations = 10000
piece_blank = 0
piece_x = 1
piece_o = 2

score_win = 6
score_tie = 5
score_lose = 4
score_max = 9
score_min = 2

function look_for_winner( board )
    p = board[ 1 ]
    if piece_blank != p
        if p == board[2] && p == board[3]
            return p
        end
        if p == board[4] && p == board[7]
            return p
        end
    end

    p = board[4]
    if piece_blank != p && p == board[5] && p == board[6]
        return p
    end

    p = board[7]
    if piece_blank != p && p == board[8] && p == board[9]
        return p
    end

    p = board[2]
    if piece_blank != p && p == board[5] && p == board[8]
        return p
    end

    p = board[3]
    if piece_blank != p && p == board[6] && p == board[9]
        return p
    end

    p = board[5]
    if piece_blank != p
        if p == board[1] && p == board[9]
            return p
        end
        if p == board[3] && p == board[7]
            return p
        end
    end

    return piece_blank
end

function pos1func( b )
    p = b[1]
    if ( ( p == b[2] && p == b[3] ) ||
         ( p == b[4] && p == b[7] ) ||
         ( p == b[5] && p == b[9] ) )
         return p
    end
    return piece_blank
end

function pos2func( b )
    p = b[2]
    if ( ( p == b[1] && p == b[3] ) ||
         ( p == b[5] && p == b[8] ) )
         return p
    end
    return piece_blank
end

function pos3func( b )
    p = b[3]
    if ( ( p == b[1] && p == b[2] ) ||
         ( p == b[6] && p == b[9] ) ||
         ( p == b[5] && p == b[7] ) )
         return p
    end
    return piece_blank
end

function pos4func( b )
    p = b[4]
    if ( ( p == b[5] && p == b[6] ) ||
         ( p == b[1] && p == b[7] ) )
         return p
    end
    return piece_blank
end

function pos5func( b )
    p = b[5]
    if ( ( p == b[1] && p == b[9] ) ||
         ( p == b[3] && p == b[7] ) ||
         ( p == b[2] && p == b[8] ) ||
         ( p == b[4] && p == b[6] ) )
         return p
    end
    return piece_blank
end

function pos6func( b )
    p = b[6]
    if ( ( p == b[4] && p == b[5] ) ||
         ( p == b[3] && p == b[9] ) )
         return p
    end
    return piece_blank
end

function pos7func( b )
    p = b[7]
    if ( ( p == b[8] && p == b[9] ) ||
         ( p == b[1] && p == b[4] ) ||
         ( p == b[5] && p == b[3] ) )
         return p
    end
    return piece_blank
end

function pos8func( b )
    p = b[8]
    if ( ( p == b[7] && p == b[9] ) ||
         ( p == b[2] && p == b[5] ) )
         return p
    end
    return piece_blank
end

function pos9func( b )
    p = b[9]
    if ( ( p == b[7] && p == b[8] ) ||
         ( p == b[3] && p == b[6] ) ||
         ( p == b[1] && p == b[5] ) )
         return p
    end
    return piece_blank
end

move_functions = [ pos1func, pos2func, pos3func, pos4func, pos5func, pos6func, pos7func, pos8func, pos9func ]

function min_max( board, alpha, beta, depth, move )
    # debugging only, and non-atomic so only works when single-threaded
    #global evaluated
    #evaluated += 1

    if depth >= 4
        # the function table is a little faster than look_for_winner
        #p = look_for_winner( board )
        p = move_functions[ move ]( board )

        if piece_blank != p
            if piece_x == p
                return score_win
            end

            return score_lose
        end

        if 8 == depth
            return score_tie
        end
    end

    if 0 != ( depth & 1 )
        value = score_min
        pieceMove = piece_x
    else
        value = score_max
        pieceMove = piece_o
    end

    for x in 1:9
        if piece_blank == board[ x ]
            board[ x ] = pieceMove
            score = min_max( board, alpha, beta, depth + 1, x )
            board[ x ] = piece_blank

            if 0 != ( depth & 1 )
                if score_win == score
                    return score_win
                end
                if score > value
                    value = score
                end
                if value > alpha
                    alpha = value
                end
                if alpha >= beta
                    return value
                end
            else
                if score_lose == score
                    return score_lose
                end
                if score < value
                    value = score
                end
                if value < beta
                    beta = value
                end
                if beta <= alpha
                    return value
                end
            end
        end
    end

    return value
end

function run_board( move )
    b = [ 0, 0, 0, 0, 0, 0, 0, 0, 0 ]
    b[ move ] = piece_x

    for i in 1:iterations
        score = min_max( b, score_min, score_max, 0, move )

        # debugging
        #if score_tie != score
        #    println( "bug: non-tie game" )
        #end
    end
end

function run_app()
    global evaluated = 0
    serial_start_time = time_ns()

    run_board( 1 )
    run_board( 2 )
    run_board( 5 )

    serial_evaluated = evaluated
    evaluated = 0
    serial_end_time = time_ns()
    serial_elapsed_time = serial_end_time - serial_start_time
    serial_elapsed_time /= 1000000
    serial_elapsed_time_seconds = serial_elapsed_time / 1000
    serial_elapsed_time_iteration = serial_elapsed_time / iterations

    moves = [ 1, 2, 5 ]
    parallel_start_time = time_ns()

    @threads for m in moves
        run_board( m )
    end

    parallel_evaluated = evaluated
    evaluated = 0
    parallel_end_time = time_ns()
    parallel_elapsed_time = parallel_end_time - parallel_start_time
    parallel_elapsed_time /= 1000000
    parallel_elapsed_time_seconds = parallel_elapsed_time / 1000
    parallel_elapsed_time_iteration = parallel_elapsed_time / iterations

    println( "serial moves evaluated: $serial_evaluated" )
    println( "  elapsed time: $serial_elapsed_time_seconds seconds" )
    println( "  elapsed time per iteration $serial_elapsed_time_iteration ms" )

    println( "parallel moves evaluated: $parallel_evaluated" )
    println( "  elapsed time: $parallel_elapsed_time_seconds seconds" )
    println( "  elapsed time per iteration $parallel_elapsed_time_iteration ms" )
end

run_app()

