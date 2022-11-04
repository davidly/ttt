#include <stdio.h>

#ifdef _MSC_VER

    #include <windows.h>
    #include <time.h>

    #if _MSC_VER > 1200  // not sure when this actually starts working
        #define USE_CHRONO
    #endif

#else // _MSC_VER

    #define USE_CHRONO
    #include <pthread.h>
    #include <thread>
    #include <unistd.h>
    #include <cstring>

#endif // _MSC_VER

#ifdef USE_CHRONO

    #include <chrono>
    using namespace std::chrono;

    typedef high_resolution_clock::time_point ticktype;
    ticktype GetTicks() { return high_resolution_clock::now(); }
    long GetMilliseconds( ticktype nowTicks, ticktype thenTicks )
    {
        return (long) duration_cast<std::chrono::milliseconds>( nowTicks - thenTicks ).count();
    }

#else // USE_CHRONO

    typedef clock_t ticktype;
    ticktype GetTicks() { return clock(); }
    long GetMilliseconds( ticktype nowTicks, ticktype thenTicks )
    {
        return nowTicks - thenTicks;
    }

#endif // USE_CHRONO

// these are needed when compiling with a recent C++ compiler and an old linker so the binary can target Windows XP

#ifdef OLDSYMBOLS
extern "C" void __scrt_exe_initialize_mta() {}
extern "C" void _filter_x86_sse2_floating_point_exception() {}
#endif

const bool ABPrune = true;
const bool WinLosePrune = true;
const int SCORE_WIN = 6;
const int SCORE_TIE = 5;
const int SCORE_LOSE = 4;
const int SCORE_MAX = 9;
const int SCORE_MIN = 2;
const int Iterations = 100000;

const char PieceX = 1;
const char PieceO = 2;
const char PieceBlank = 0;

static void Usage()
{
    printf( "Usage: ttt\n" );
    printf( "  Tic Tac Toe" );

    exit( 1 );
} //Usage

char pos0func( char * board )
{
    char x = board[0];
    
    if ( ( x == board[1] && x == board[2] ) ||
         ( x == board[3] && x == board[6] ) ||
         ( x == board[4] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos0func

char pos1func( char * board )
{
    char x = board[1];
    
    if ( ( x == board[0] && x == board[2] ) ||
         ( x == board[4] && x == board[7] ) )
        return x;
    return PieceBlank;
} //pos1func

char pos2func( char * board )
{
    char x = board[2];
    
    if ( ( x == board[0] && x == board[1] ) ||
         ( x == board[5] && x == board[8] ) ||
         ( x == board[4] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos2func

char pos3func( char * board )
{
    char x = board[3];
    
    if ( ( x == board[4] && x == board[5] ) ||
         ( x == board[0] && x == board[6] ) )
        return x;
    return PieceBlank;
} //pos3func

char pos4func( char * board )
{
    char x = board[4];
    
    if ( ( x == board[0] && x == board[8] ) ||
         ( x == board[2] && x == board[6] ) ||
         ( x == board[1] && x == board[7] ) ||
         ( x == board[3] && x == board[5] ) )
        return x;
    return PieceBlank;
} //pos4func

char pos5func( char * board )
{
    char x = board[5];
    
    if ( ( x == board[3] && x == board[4] ) ||
         ( x == board[2] && x == board[8] ) )
        return x;
    return PieceBlank;
} //pos5func

char pos6func( char * board )
{
    char x = board[6];
    
    if ( ( x == board[7] && x == board[8] ) ||
         ( x == board[0] && x == board[3] ) ||
         ( x == board[4] && x == board[2] ) )
        return x;
    return PieceBlank;
} //pos6func

char pos7func( char * board )
{
    char x = board[7];
    
    if ( ( x == board[6] && x == board[8] ) ||
         ( x == board[1] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos7func

char pos8func( char * board )
{
    char x = board[8];
    
    if ( ( x == board[6] && x == board[7] ) ||
         ( x == board[2] && x == board[5] ) ||
         ( x == board[0] && x == board[4] ) )
        return x;
    return PieceBlank;
} //pos8func

typedef char (*winnerfunc)( char * board );

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

char LookForWinner( char * board )
{
    // about 8% faster with loops unrolled

    char p = board[0];
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

int MinMax( char * board, int alpha, int beta, int depth, int move )
{
    //InterlockedIncrement( &g_Moves );
    //g_Moves++;

    // scores are always with respect to X.
    // maximize on X moves; minimize on O moves
    // # of chars on board = 1 + depth
    // maximize and X moves are on odd depths.

    if ( depth >= 4 )
    {
        //char p = LookForWinner( board );
        char p = winner_functions[ move ]( board );

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
    char pieceMove;

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

#ifdef _MSC_VER
    DWORD WINAPI
#else
    void * 
#endif

TTTThreadProc( void * param )
{
    size_t position = (size_t) param;

    char board[ 9 ];
    memset( board, 0, sizeof board );
    board[ position ] = PieceX;

    for ( int times = 0; times < Iterations; times++ )
        MinMax( board, SCORE_MIN, SCORE_MAX, 0, position );

    return 0;
} //TTTThreadProc

int main( int argc, char * argv[] )
{
#ifdef _MSC_VER
#ifdef _M_ARM64
    SetProcessAffinityMask( GetCurrentProcess(), 0x70 ); // sq3: 0x7 efficiency cores, 0x70 performance cores
#endif
#endif

    ticktype startParallel = GetTicks();

#ifdef _MSC_VER
    HANDLE aHandles[ 2 ];
    DWORD dwID; // required for Win98. On NT you can pass 0.
    aHandles[ 0 ] = CreateThread( 0, 0, TTTThreadProc, (void *) 0, 0, &dwID );
    aHandles[ 1 ] = CreateThread( 0, 0, TTTThreadProc, (void *) 4, 0, &dwID );
#else
    pthread_t threads[ 2 ];
    pthread_create( &threads[ 0 ], 0, TTTThreadProc, (void *) 0 );
    pthread_create( &threads[ 1 ], 0, TTTThreadProc, (void *) 4 );
#endif

    TTTThreadProc( (void *) 1 );

#ifdef _MSC_VER
    WaitForMultipleObjects( 2, aHandles, TRUE, INFINITE );
    CloseHandle( aHandles[ 0 ] );
    CloseHandle( aHandles[ 1 ] );
#else
    pthread_join( threads[ 0 ], 0 );
    pthread_join( threads[ 1 ], 0 );
#endif

    ticktype endParallel = GetTicks();
    int parallelMoves = g_Moves;
    g_Moves = 0;
    
    ticktype startSerial = GetTicks();

    TTTThreadProc( (void *) 0 );
    TTTThreadProc( (void *) 1 );
    TTTThreadProc( (void *) 4 );

    ticktype endSerial = GetTicks();

    if ( 0 != g_Moves )
        printf( "moves examined: %d, parallel %d\n", g_Moves, parallelMoves );

    printf( "ran %d iterations\n", Iterations );
    printf( "parallel milliseconds: %ld\n", GetMilliseconds( endParallel, startParallel ) );
    printf( "serial   milliseconds: %ld\n", GetMilliseconds( endSerial, startSerial ) );

    return 0;
} //main


