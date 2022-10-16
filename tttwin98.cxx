#include <stdio.h>
#include <windows.h>

const bool ABPrune = true;
const bool WinLosePrune = true;
const int SCORE_WIN = 6;
const int SCORE_TIE = 5;
const int SCORE_LOSE = 4;
const int SCORE_MAX = 9;
const int SCORE_MIN = 2;
const int Iterations = 100000;
const bool EnableDebug = false;

const BYTE PieceX = 1;
const BYTE PieceO = 2;
const BYTE PieceBlank = 0;

static void Usage()
{
    printf( "Usage: ttt\n" );
    printf( "  Tic Tac Toe" );

    exit( 1 );
} //Usage

BYTE pos0func( BYTE * board )
{
    BYTE x = board[0];
    
    if ( ( x == board[1] && x == board[2] ) ||
         ( x == board[3] && x == board[6] ) ||
         ( x == board[4] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos0func

BYTE pos1func( BYTE * board )
{
    BYTE x = board[1];
    
    if ( ( x == board[0] && x == board[2] ) ||
         ( x == board[4] && x == board[7] ) )
        return x;
    return PieceBlank;
} //pos1func

BYTE pos2func( BYTE * board )
{
    BYTE x = board[2];
    
    if ( ( x == board[0] && x == board[1] ) ||
         ( x == board[5] && x == board[8] ) ||
         ( x == board[4] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos2func

BYTE pos3func( BYTE * board )
{
    BYTE x = board[3];
    
    if ( ( x == board[4] && x == board[5] ) ||
         ( x == board[0] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos3func

BYTE pos4func( BYTE * board )
{
    BYTE x = board[4];
    
    if ( ( x == board[0] && x == board[8] ) ||
         ( x == board[2] && x == board[6] ) ||
         ( x == board[1] && x == board[7] ) ||
         ( x == board[3] && x == board[5] ) )
        return x;
    return PieceBlank;
} //pos4func

BYTE pos5func( BYTE * board )
{
    BYTE x = board[5];
    
    if ( ( x == board[3] && x == board[4] ) ||
         ( x == board[2] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos5func

BYTE pos6func( BYTE * board )
{
    BYTE x = board[6];
    
    if ( ( x == board[7] && x == board[8] ) ||
         ( x == board[0] && x == board[3] ) ||
         ( x == board[4] && x == board[2] ) )
        return x;
    return PieceBlank;
} //pos6func

BYTE pos7func( BYTE * board )
{
    BYTE x = board[7];
    
    if ( ( x == board[6] && x == board[8] ) ||
         ( x == board[1] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos7func

BYTE pos8func( BYTE * board )
{
    BYTE x = board[8];
    
    if ( ( x == board[6] && x == board[7] ) ||
         ( x == board[2] && x == board[5] ) ||
         ( x == board[0] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos8func

typedef BYTE (*winnerfunc)( BYTE * board );

winnerfunc winner_functions[] =
{
    pos0func,
    pos1func,
    pos2func,
    pos3func,
    pos4func,
    pos5func,
    pos6func,
    pos7func,
    pos8func,
};

BYTE LookForWinner( BYTE * board )
{
    // about 8% faster with loops unrolled

    BYTE p = board[0];
    if ( PieceBlank != p )
    {
        if ( p == board[1] && p == board[2] )
            return p;

        if ( p == board[3] && p == board[6] )
            return p;
    }

    p = board[3];
    if ( PieceBlank != p && p == board[4] && p == board[5] )
        return p;

    p = board[6];
    if ( PieceBlank != p && p == board[7] && p == board[8] )
        return p;

    p = board[1];
    if ( PieceBlank != p && p == board[4] && p == board[7] )
        return p;

    p = board[2];
    if ( PieceBlank != p && p == board[5] && p == board[8] )
        return p;

    p = board[4];
    if ( PieceBlank != p )
    {
        if ( ( p == board[0] ) && ( p == board[8] ) )
            return p;

        if ( ( p == board[2] ) && ( p == board[6] ) )
            return p;
    }

    return PieceBlank;
} //LookForWinner

void Sp( int x )
{
    for ( int i = 0; i < x; i++ )
        printf( " " );
}

unsigned int g_Moves = 0;

int MinMax( BYTE * board, int alpha, int beta, int depth, int move )
{
    //InterlockedIncrement( &g_Moves );
    //g_Moves++;

    // scores are always with respect to X.
    // maximize on X moves; minimize on O moves
    // # of BYTEs on board = 1 + depth
    // maximize and X moves are on odd depths.

    if ( depth >= 4 )
    {
        //BYTE p = LookForWinner( board );
        BYTE p = winner_functions[ move ]( board );

        if ( PieceBlank != p )
        {
            if ( PieceX == p )
                return SCORE_WIN;

            return SCORE_LOSE;
        }

        if ( 8 == depth )
            return SCORE_TIE;
    }

    int value;
    BYTE pieceMove;

    if ( depth & 1 ) //maximize
    {
        value = SCORE_MIN;
        pieceMove = PieceX;
    }
    else
    {
        value = SCORE_MAX;
        pieceMove = PieceO;
    }

    for ( int p = 0; p < 9; p++ )
    {
        if ( PieceBlank == board[ p ] )
        {
            board[p] = pieceMove;
            int score = MinMax( board, alpha, beta, depth + 1, p );
            board[p] = PieceBlank;

            if ( depth & 1 ) //maximize 
            {
                if ( WinLosePrune && SCORE_WIN == score )
                    return SCORE_WIN;

                if ( score > value )
                    value = score;

                if ( ABPrune )
                {
                    if ( value > alpha )
                        alpha = value;

                    if ( alpha >= beta )
                        return value;
                }
            }
            else
            {
                if ( WinLosePrune && SCORE_LOSE == score )
                    return SCORE_LOSE;

                if ( score < value )
                    value = score;

                if ( ABPrune )
                {
                    if ( value < beta )
                        beta = value;

                    if ( beta <= alpha )
                        return value;
                }
            }
        }
    }

    return value;
} //MinMax

DWORD WINAPI TTTThreadProc( LPVOID param )
{
    size_t position = (size_t) param;

    BYTE board[ 9 ];
    memset( board, 0, sizeof board );
    board[ position ] = PieceX;

    for ( int times = 0; times < Iterations; times++ )
        MinMax( board, SCORE_MIN, SCORE_MAX, 0, position );

    return 0;
} //TTTThreadProc

extern "C" int __cdecl main( int argc, char *argv[] )
{
    // Only 3 starting moves aren't transpositions and/or mirrors of other moves.

    DWORD startParallelTicks = GetTickCount();
    HANDLE aHandles[ 2 ];
    DWORD dwID;

    aHandles[ 0 ] = CreateThread( 0, 0, TTTThreadProc, (LPVOID) 0, 0, &dwID );
    aHandles[ 1 ] = CreateThread( 0, 0, TTTThreadProc, (LPVOID) 4, 0, &dwID );

    TTTThreadProc( (LPVOID) 1 );

    WaitForMultipleObjects( 2, aHandles, TRUE, INFINITE );

    for ( size_t i = 0; i < 2; i++ )
        CloseHandle( aHandles[ i ] );

    DWORD endParallelTicks = GetTickCount();
    int parallelMoves = g_Moves;
    g_Moves = 0;
    
    DWORD startSerialTicks = GetTickCount();

    TTTThreadProc( (LPVOID) 0 );
    TTTThreadProc( (LPVOID) 1 );
    TTTThreadProc( (LPVOID) 4 );

    DWORD endSerialTicks = GetTickCount();

    if ( 0 != g_Moves )
        printf( "moves examined: %d, parallel %d\n", g_Moves, parallelMoves );

    printf( "ran %d iterations\n", Iterations );
    printf( "parallel milliseconds: %d\n", endParallelTicks - startParallelTicks );
    printf( "serial   milliseconds: %d\n", endSerialTicks - startSerialTicks );

    return 0;
} //Main


