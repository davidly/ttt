-- prove you can't win in nuclear war or tic-tac-toe
-- lua arrays start at 1, so the board layout is:
--
--  1  2  3
--  4  5  6
--  7  8  9

evaluated = 0
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
    if piece_blank ~= p then
        if p == board[2] and p == board[3] then
            return p
        end
        if p == board[4] and p == board[7] then
            return p
        end
    end

    p = board[4]
    if piece_blank ~= p and p == board[5] and p == board[6] then
        return p
    end

    p = board[7]
    if piece_blank ~= p and p == board[8] and p == board[9] then
        return p
    end

    p = board[2]
    if piece_blank ~= p and p == board[5] and p == board[8] then
        return p
    end

    p = board[3]
    if piece_blank ~= p and p == board[6] and p == board[9] then
        return p
    end

    p = board[5]
    if piece_blank ~= p then
        if p == board[1] and p == board[9] then
            return p
        end
        if p == board[3] and p == board[7] then
            return p
        end
    end

    return piece_blank
end

function pos1func( b )
    p = b[1]
    if ( ( p == b[2] and p == b[3] ) or
         ( p == b[4] and p == b[7] ) or
         ( p == b[5] and p == b[9] ) ) then
         return p
    end
    return piece_blank
end

function pos2func( b )
    p = b[2]
    if ( ( p == b[1] and p == b[3] ) or
         ( p == b[5] and p == b[8] ) ) then
         return p
    end
    return piece_blank
end

function pos3func( b )
    p = b[3]
    if ( ( p == b[1] and p == b[2] ) or
         ( p == b[6] and p == b[9] ) or
         ( p == b[5] and p == b[7] ) ) then
         return p
    end
    return piece_blank
end

function pos4func( b )
    p = b[4]
    if ( ( p == b[5] and p == b[6] ) or
         ( p == b[1] and p == b[7] ) ) then
         return p
    end
    return piece_blank
end

function pos5func( b )
    p = b[5]
    if ( ( p == b[1] and p == b[9] ) or
         ( p == b[3] and p == b[7] ) or
         ( p == b[2] and p == b[8] ) or
         ( p == b[4] and p == b[6] ) ) then
         return p
    end
    return piece_blank
end

function pos6func( b )
    p = b[6]
    if ( ( p == b[4] and p == b[5] ) or
         ( p == b[3] and p == b[9] ) ) then
         return p
    end
    return piece_blank
end

function pos7func( b )
    p = b[7]
    if ( ( p == b[8] and p == b[9] ) or
         ( p == b[1] and p == b[4] ) or
         ( p == b[5] and p == b[3] ) ) then
         return p
    end
    return piece_blank
end

function pos8func( b )
    p = b[8]
    if ( ( p == b[7] and p == b[9] ) or
         ( p == b[2] and p == b[5] ) ) then
         return p
    end
    return piece_blank
end

function pos9func( b )
    p = b[9]
    if ( ( p == b[7] and p == b[8] ) or
         ( p == b[3] and p == b[6] ) or
         ( p == b[1] and p == b[5] ) ) then
         return p
    end
    return piece_blank
end

move_functions = { pos1func, pos2func, pos3func, pos4func, pos5func, pos6func, pos7func, pos8func, pos9func }

function min_max( board, alpha, beta, depth, move )
    evaluated = evaluated + 1

    if depth >= 4 then
        -- the function table is about 30% faster
        --local w = look_for_winner( board )
        local w = move_functions[ move ]( board )

        if piece_blank ~= w then
            if piece_x == w then return score_win end
            return score_lose
        end

        if 8 == depth then return score_tie end
    end

    local value
    local pieceMove

    if 0 ~= ( depth % 2 ) then
        value = score_min
        pieceMove = piece_x
    else
        value = score_max
        pieceMove = piece_o
    end

    for x = 1, 9 do
        if piece_blank == board[ x ] then
            board[ x ] = pieceMove
            local score = min_max( board, alpha, beta, depth + 1, x )
            board[ x ] = piece_blank

            if 0 ~= ( depth % 2 ) then
                if score_win == score then return score_win end
                if score > value then value = score end
                if value > alpha then alpha = value end
                if alpha >= beta then return value end
            else
                if score_lose == score then return score_lose end
                if score < value then value = score end
                if value < beta then beta = value end
                if beta <= alpha then return value end
            end
        end
    end

    return value
end

function run_board( move )
    local start_state = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    start_state[ move ] = piece_x

    for i = 1, iterations do
        score = min_max( start_state, score_min, score_max, 0, move )
    end

    return evaluated
end

function run_app()
    serial_start_time = os.clock()
    run_board( 1 )
    run_board( 2 )
    run_board( 5 )
    serial_end_time = os.clock()

    serial_elapsed_time = serial_end_time - serial_start_time
    print( "serial elapsed time ", serial_elapsed_time )
    print( "  per iteration: ", serial_elapsed_time / iterations * 1000, " ms" )

    --print( "moves evaluated: ", evaluated )
end

--io.write("lua version ",_VERSION,"!\n")

-- comment run_app() out when using LuaJit (run_board is called from C++ instead)

run_app()
