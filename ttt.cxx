// this version uses PPL and OpenMP. It's slower than ttt_all.cxx, which uses threads more directly. This version is obsolete.
//

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <chrono>

using namespace std;
using namespace std::chrono;

const int Iterations = 10000;

#ifdef _MSC_VER

    #define USE_PPL
    #include <ppl.h>
    #include <windows.h>

    using namespace concurrency;

#else // likely G++ / Clang++

    #define __forceinline

    #ifndef __min
        #define __min( a, b ) ( a < b ) ? a : b
    #endif

    #ifndef __max
        #define __max( a, b ) ( a > b ) ? a : b
    #endif

    #ifndef byte
        typedef unsigned char byte;
    #endif

    #ifndef __cdecl
        #define __cdecl
    #endif

#endif

const bool ABPrune = true;
const bool WinLosePrune = true;
const int SCORE_WIN = 6;
const int SCORE_TIE = 5;
const int SCORE_LOSE = 4;
const int SCORE_MAX = 9;
const int SCORE_MIN = 2;

static void Usage()
{
    printf( "Usage: ttt\n" );
    printf( "  Tic Tac Toe" );

    exit( 1 );
} //Usage

enum Piece : byte { blank = 0, X = 1, O = 2 };

Piece pos0func( Piece board[9] )
{
    Piece x = board[0];
    
    if ( ( x == board[1] && x == board[2] ) ||
         ( x == board[3] && x == board[6] ) ||
         ( x == board[4] && x == board[8] ) )
        return x;
    return Piece::blank;
} //pos0func

Piece pos1func( Piece board[9] )
{
    Piece x = board[1];
    
    if ( ( x == board[0] && x == board[2] ) ||
         ( x == board[4] && x == board[7] ) )
        return x;
    return Piece::blank;
} //pos1func

Piece pos2func( Piece board[9] )
{
    Piece x = board[2];
    
    if ( ( x == board[0] && x == board[1] ) ||
         ( x == board[5] && x == board[8] ) ||
         ( x == board[4] && x == board[6] ) )
        return x;
    return Piece::blank;
} //pos2func

Piece pos3func( Piece board[9] )
{
    Piece x = board[3];
    
    if ( ( x == board[4] && x == board[5] ) ||
         ( x == board[0] && x == board[6] ) )
        return x;
    return Piece::blank;
} //pos3func

Piece pos4func( Piece board[9] )
{
    Piece x = board[4];
    
    if ( ( x == board[0] && x == board[8] ) ||
         ( x == board[2] && x == board[6] ) ||
         ( x == board[1] && x == board[7] ) ||
         ( x == board[3] && x == board[5] ) )
        return x;
    return Piece::blank;
} //pos4func

Piece pos5func( Piece board[9] )
{
    Piece x = board[5];
    
    if ( ( x == board[3] && x == board[4] ) ||
         ( x == board[2] && x == board[8] ) )
        return x;
    return Piece::blank;
} //pos5func

Piece pos6func( Piece board[9] )
{
    Piece x = board[6];
    
    if ( ( x == board[7] && x == board[8] ) ||
         ( x == board[0] && x == board[3] ) ||
         ( x == board[4] && x == board[2] ) )
        return x;
    return Piece::blank;
} //pos6func

Piece pos7func( Piece board[9] )
{
    Piece x = board[7];
    
    if ( ( x == board[6] && x == board[8] ) ||
         ( x == board[1] && x == board[4] ) )
        return x;
    return Piece::blank;
} //pos7func

Piece pos8func( Piece board[9] )
{
    Piece x = board[8];
    
    if ( ( x == board[6] && x == board[7] ) ||
         ( x == board[2] && x == board[5] ) ||
         ( x == board[0] && x == board[4] ) )
        return x;
    return Piece::blank;
} //pos8func

typedef Piece (*winnerfunc)(Piece board[9]);

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

class Board
{
    public:

    Piece board[9];

    Board()
    {
        memset( &board, 0, sizeof board );
    }

    void Clear()
    {
        memset( &board, 0, sizeof board );
    }

    void Print()
    {
        for ( int r = 0; r < 3; r++ )
        {
            for ( int c = 0; c < 3; c++ )
            {
                Piece p = board[r * 3 + c];
                printf( "%s ", Piece::blank == p ? " " : Piece::X == p ? "X" : "O" );
            }

            printf( "\n" );
        }
    }
    
    Piece LookForWinner()
    {
        // about 8% faster with loops unrolled

        Piece p = board[0];
        if ( Piece::blank != p )
        {
            if ( p == board[1] && p == board[2] )
                return p;

            if ( p == board[3] && p == board[6] )
                return p;
        }

        p = board[3];
        if ( Piece::blank != p && p == board[4] && p == board[5] )
            return p;

        p = board[6];
        if ( Piece::blank != p && p == board[7] && p == board[8] )
            return p;

        p = board[1];
        if ( Piece::blank != p && p == board[4] && p == board[7] )
            return p;

        p = board[2];
        if ( Piece::blank != p && p == board[5] && p == board[8] )
            return p;

        p = board[4];
        if ( Piece::blank != p )
        {
            if ( ( p == board[0] ) && ( p == board[8] ) )
                return p;

            if ( ( p == board[2] ) && ( p == board[6] ) )
                return p;
        }

        return Piece::blank;
    } //LookForWinner
};

void Sp( int x )
{
    for ( int i = 0; i < x; i++ )
        printf( " " );
}

unsigned int g_Moves = 0;

int MinMax( Board &b, int alpha, int beta, int depth, int move )
{
    //InterlockedIncrement( &g_Moves );
    //g_Moves++;

    // scores are always with respect to X.
    // maximize on X moves; minimize on O moves
    // # of pieces on board = 1 + depth
    // maximize and X moves are on odd depths.

    if ( depth >= 4 )
    {
        //Piece p = b.LookForWinner();
        Piece p = winner_functions[ move ]( b.board );

        if ( Piece::blank != p )
        {
            if ( Piece::X == p )
                return SCORE_WIN;

            return SCORE_LOSE;
        }

        if ( 8 == depth )
            return SCORE_TIE;
    }

    int value;
    Piece pieceMove;

    if ( depth & 1 ) //maximize
    {
        value = SCORE_MIN;
        pieceMove = Piece::X;
    }
    else
    {
        value = SCORE_MAX;
        pieceMove = Piece::O;
    }

    for ( int p = 0; p < 9; p++ )
    {
        if ( Piece::blank == b.board[ p ] )
        {
            b.board[p] = pieceMove;
            int score = MinMax( b, alpha, beta, depth + 1, p );
            b.board[p] = Piece::blank;

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

void RunBoard( int move, int iterations = Iterations )
{
    Board b;
    b.board[ move ] = Piece::X;

    for ( int i = 0; i < iterations; i++ )
        MinMax( b, SCORE_MIN, SCORE_MAX, 0, move );
} //RunBoard

void PrintNumberWithCommas( long long n )
{
    if ( n < 0 )
    {
        printf( "-" );
        PrintNumberWithCommas( -n );
        return;
    }
   
    if ( n < 1000 )
    {
        printf( "%lld", n );
        return;
    }

    PrintNumberWithCommas( n / 1000 );
    printf( ",%03lld", n % 1000 );
} //PrintNumberWithCommas

extern "C" int __cdecl main( int argc, char *argv[] )
{
#if false
    RunBoard( 0 );
    RunBoard( 1 );
    RunBoard( 4 );
    printf( "moves: %d\n", g_Moves );
    exit( 0 );
#endif

    int parallelMoves = 0;

    high_resolution_clock::time_point tStart = high_resolution_clock::now();

#ifdef USE_PPL
    parallel_for( 0, 3, [&] ( int i )
#else
    #pragma omp parallel for schedule(nonmonotonic:dynamic)
    for ( int i = 0; i < 3; i++ )
#endif
    {
        if ( 0 == i )
            RunBoard( 0 );
        else if ( 1 == i )
            RunBoard( 1 );
        else if ( 2 == i )
            RunBoard( 4 );
    }

#ifdef USE_PPL
    );
#endif

    parallelMoves = g_Moves;
    g_Moves = 0;
    high_resolution_clock::time_point tAfterMultiThreaded = high_resolution_clock::now();

    RunBoard( 0 );
    RunBoard( 1 );
    RunBoard( 2 );

    high_resolution_clock::time_point tAfterSingleThreaded = high_resolution_clock::now();

    long long mtTime = duration_cast<std::chrono::milliseconds>( tAfterMultiThreaded - tStart ).count();
    long long stTime = duration_cast<std::chrono::milliseconds>( tAfterSingleThreaded - tAfterMultiThreaded ).count();

    printf( "total for %d runs multi-threaded:  ", Iterations ); PrintNumberWithCommas( mtTime ); printf( " milliseconds\n" );
    printf( "total for %d runs single-threaded: ", Iterations ); PrintNumberWithCommas( stTime ); printf( " milliseconds\n" );

    printf( "moves examined: %d, parallel %d\n", g_Moves, parallelMoves );

    return 0;
} //Main

